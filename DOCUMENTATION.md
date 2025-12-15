# System Documentation

## **COMMUNICATION BRIDGE**

```verilog
reg miso_reg;
reg byte_sync_reg;
reg [7:0] data_in_reg;
```

These registers implement the **output interface of the SPI bridge**.  
This design **explicitly separates the SPI clock domain (`sclk`) from the internal system clock domain (`clk`)**, ensuring correct operation even when the two clocks are equal, close in frequency, or asynchronous.

### **SPI Clock Domain Registers**

```verilog
reg [2:0] bit_cnt;
reg [7:0] shift_reg;
reg [7:0] captured_data;
reg [7:0] byte_counter;
```

These registers operate exclusively in the **SPI clock domain**:

- **`bit_cnt`** — tracks the current bit position (0–7) within a byte  
- **`shift_reg`** — shift register used to accumulate incoming **MOSI** bits  
- **`captured_data`** — stores the completed byte after all 8 bits are received  
- **`byte_counter`** — increments once per received byte and acts as a safe event indicator for clock-domain crossing  

### **Receiving Data (MOSI) — `posedge sclk`**

```verilog
always @(posedge sclk or negedge rst_n)
```

Incoming SPI data is captured on the **rising edge of `sclk`**, following standard SPI timing.

### Operation

- On reset: all SPI-domain registers are cleared.
- When **`cs_n` is high** (inactive): `bit_cnt` is reset.
- When **`cs_n` is low** (active):
  - `shift_reg` shifts left by one bit;  
  - The current `mosi` value is inserted into the LSB;
  - `bit_cnt` increments.

When **`bit_cnt == 7`**:

- `{shift_reg[6:0], mosi}` is stored in **`captured_data`**;
- **`byte_counter`** increments to indicate a completed byte;
- `bit_cnt` resets for the next byte.

This guarantees **accurate byte reconstruction** in the SPI clock domain.

### **Transmitting Data (MISO) — `negedge sclk`**

```verilog
always @(negedge sclk or negedge rst_n)
```

Outgoing SPI data is driven on the **falling edge of `sclk`**, ensuring the master samples stable data on the next rising edge.

### Operation

- On reset: `miso_reg` is cleared  
- When **`cs_n` is low**:
  - The bit at position ``7 - bit_cnt`` from `data_out` is driven onto **`miso_reg`**

The expression ``7 - bit_cnt`` ensures **MSB-first transmission**, which is standard for SPI.

### **MISO Initialization on Chip-Select Assertion**

```verilog
always @(negedge cs_n or negedge rst_n)
```

This block initializes the MISO line at the **start of every SPI transaction**.

- On reset: `miso_reg` is cleared  
- When **`cs_n` transitions low**:
  - `miso_reg` is loaded with `data_out[7]`

This guarantees the **first output bit is valid before the first clock edge**.

### **Clock-Domain Crossing (SPI → Internal `clk`)**

```verilog
reg [7:0] bc_sync1, bc_sync2, bc_prev;
```

Because **`byte_counter`** is updated in the **SPI clock domain**, it must be safely transferred into the **internal `clk` domain** (master).

This is done using a **two-stage synchronizer** followed by a previous-value register:

```verilog
bc_sync1 <= byte_counter;
bc_sync2 <= bc_sync1;
bc_prev <= bc_sync2;
```

- **`bc_sync1`** and **`bc_sync2`** safely synchronize the counter;
- **`bc_prev`** stores the last synchronized value.

### **Byte Completion Detection (`byte_sync`)**

```verilog
always @(posedge clk or negedge rst_n)
```

This block generates a **single-cycle pulse** when a new SPI byte becomes available.

### Logic

- On reset: all synchronization registers and outputs are cleared.
- On each `clk` edge: The current synchronized byte counter is compared with its previous value. 

When **`bc_sync2 != bc_prev`**:

- **`byte_sync_reg`** is asserted for **one `clk` cycle** (pulse);
- **`data_in_reg`** is updated with **`captured_data`** (byte read).

## INSTRUCTION DECODER

The instruction decoder receives bytes from the SPI bridge and interprets them either as **instruction bytes** or **data bytes**, depending on the current internal state. Before implementing the decoding logic, the necessary output registers are defined and connected to their corresponding module outputs through continuous assignments. A single-bit `state` register is also introduced to indicate whether the module is currently processing an instruction (`state = 0`) or receiving the data associated with that instruction (`state = 1`).

```
reg rw_reg;
reg hl_reg;
reg [5:0] addr_reg;
reg [7:0] data_out_reg;
reg [7:0] data_write_reg;
reg write_reg;
reg read_reg;

// 0 = SETUP, 1 = DATA
reg state;

assign data_out   = data_out_reg;
assign data_write = data_write_reg;
assign addr       = addr_reg;
assign read       = read_reg;
assign write      = write_reg;
```

---

### **Decoder Logic Overview**

The main decoding logic resides inside an `always` block that executes on each **posedge** of `clk` or **negedge** of `rst_n`.  
Its behavior can be summarized as follows:

---

### **1. Reset Handling**

If the reset signal is asserted (`rst_n == 0`):

- All internal registers (including control signals and outputs) are cleared to default values.
- The state machine is returned to the **SETUP** state (`state = 0`).

This ensures deterministic behavior when starting the system or recovering from reset.

---

### **2. Normal Operation**

When reset is not asserted, the decoder performs the following steps each cycle:

- `write_reg` and `read_reg` are cleared to `0` at the beginning of the cycle.
- A `case` statement selects the appropriate behavior depending on the current value of the `state` register.

---

### **State 0 – Instruction Interpretation**

When `state == 0`, the incoming byte is treated as an **instruction byte**. Its internal structure is decoded into the following fields:

- `rw_reg` – operation type (read or write), extracted from the **MSB**
- `hl_reg` – selects high or low byte (if addressing partial registers)
- `addr_reg` – 6-bit register address

The decoder then behaves differently depending on whether the operation is a **read** or a **write**:

#### **Write Operation (`rw_reg == 1`)**

- No data needs to be returned to the external master yet.
- `data_out_reg` is cleared to `0` (dummy value).

#### **Read Operation (`rw_reg == 0`)**

- The decoder loads the current value from `data_read` into `data_out_reg`, making it available for transmission back to the SPI master.
- `read_reg` is asserted (`1`), signaling that a read cycle is requested by the system.

After processing the instruction byte, the state machine transitions to:

```
state <= 1;    // proceed to DATA state
```

---

### **State 1 – Data Handling**

When `state == 1`, the decoder handles the **data byte** associated with the previously decoded instruction.

#### **Write Operation**

Only write operations require active handling in this state:

- The incoming data byte (`data_in`) is stored in `data_write_reg`.
- This value is exposed through the `data_write` output, enabling the addressed register to update its contents.
- `write_reg` is asserted (`1`), informing the system that valid write data is available.

#### **Read Operation**

Read operations do **not** require explicit action in this state; by the time state 1 is reached, the read data has already been prepared during state 0.

#### **State Reset**

At the end of state 1:

```
state <= 0;    // return to SETUP and wait for next instruction
```

The decoder waits for the next `byte_sync` signal from the SPI bridge, indicating that a new instruction byte has been received and is ready for processing.

## REGISTER BLOCK IMPLEMENTATION (`regs.v`)

This section describes only the implementation details specific to my design, not the generic architecture already provided in the assignment.

---

### **Internal Structure**

All user-visible registers (`PERIOD`, `COUNTER_EN`, `COMPARE1/2`, `PRESCALE`, `UPNOTDOWN`, `PWM_EN`, `FUNCTIONS`) are stored using Verilog `reg` variables with their exact logical width.  
Two additional internal elements are used:

- `count_reset_sh` – a 2-bit internal countdown for generating the two‑cycle active pulse for `COUNTER_RESET`.
- `data_read` – combinational multiplexer output for read operations.

---

### **Addressing Choices**

- The module receives a 6-bit address.
- 16-bit registers are split into LSB/MSB across consecutive addresses.
- Unused addresses have no effect on write and return `0x00` on read.

---

### **COUNTER_RESET Mechanism**

Writing to address `0x07` loads `count_reset_sh = 2'b11`, which decrements each clock.  
`count_reset` is high whenever the countdown is non‑zero, producing an exact two‑cycle pulse.

### **Write Logic Details**

Only meaningful bits are stored:

- Single-bit registers (`en`, `upnotdown`, `pwm_en`) use `data_write[0]`
- `FUNCTIONS` uses `data_write[1:0]`
- 16‑bit registers follow LSB/MSB splitting.

### **Read Logic Details**

The read path is a combinational multiplexer:

- 16‑bit registers return LSB/MSB halves
- Single‑bit registers are zero‑extended
- `COUNTER_RESET` always returns `0x00`
- Invalid addresses return `0x00`

### **Reset Behaviour**

Registers initialize to deterministic defaults:  
counter disabled, prescaler zero, comparators zero, PWM disabled, default down-count direction.

## COUNTER IMPLEMENTATION (`counter.v`)

### **Internal State and Prescaler**

Two 16‑bit registers:

- `r_count_val` – main up/down counter
- `r_presc_cnt` – internal prescaler counter

A combinational wire computes the prescaler target:

```
prescale_target = 1 << prescale;
```

This implements frequency division by `2^PRESCALE`.

---

### **Reset and Enable Behaviour**

- Asynchronous reset clears both registers.
- `count_reset` has highest priority and resets only counter-related registers.
- When `en = 0`, `r_count_val` holds its value while `r_presc_cnt` resets.

---

### **Prescaler and Counting Logic**

If `PRESCALE = 0`, the counter ticks every clock.  
If `PRESCALE > 0`, the prescaler increments until reaching `prescale_target − 1`, then resets and produces one tick.

---

### **Up/Down and Period Handling**

On each tick:

- **Up-counting**: increment until reaching `period`, then wrap to `0`
- **Down-counting**: decrement until `0`, then wrap to `period`

`COMPARE1` and `COMPARE2` are not used in this module; they are consumed by the PWM block.

## PWM GENERATOR IMPLEMENTATION (`pwm_gen.v`)

The PWM generator module is designed as a **purely combinational logic block**. It determines the state of the output signal (`pwm_out`) instantaneously based on the current value of the counter (`count_val`) and the configuration registers (`compare1`, `compare2`, `functions`).

### **Operational Logic**

The module uses an `always @(*)` block to evaluate conditions in a prioritized order.

#### **1. Configuration Extraction**
The `functions` register bits are mapped to readable wire names to determine the operating mode:
```verilog
wire align_mode  = functions[1]; // aligned / unaligned
wire align_right = functions[0]; // left / right aligned
```

#### **2. Reset and Safety Priorities**
Before generating anything, the module enforces some conditions:

* **Asynchronous Reset:** If `rst_n` is low, `pwm_out` is forced to `0`.
* **Enable Signal:** If `pwm_en` is low, the output is held at `0`.
* **Equality Check:** If `compare1 == compare2`, the output is forced to `0` to prevent undefined behavior in unaligned mode.

#### **3. Signal Generation Modes**
If the device is enabled, the logic selects one of the modes based on the alignment settings provided in the FUNCTIONS register:

* **Left Aligned (`functions` = `00`):**
    * The signal is high from the start of the period.
    * **Logic:** `pwm_out = 1` when `count_val <= compare1`.
    * **Edge case:** If `compare1` is 0, the output remains low.

* **Right Aligned (`functions` = `01`):**
    * The signal is high towards the end of the period.
    * **Logic:** `pwm_out = 1` when `count_val >= compare1`.

* **Unaligned Mode (`functions` = `1x`):**
    * This mode generates a pulse somewhere in the middle of the period, defined by start and stop thresholds.
    * **Logic:** `pwm_out = 1` when `count_val >= compare1` and `count_val < compare2`.

#### **Note**
The `period` signal is unused in this block because the cycle duration is managed entirely by the `counter.v` module. The generator relies solely on `count_val` and the comparison thresholds to determine the output state.