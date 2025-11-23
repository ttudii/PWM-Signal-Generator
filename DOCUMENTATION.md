# Documentation

### COMMUNICATION BRIDGE

```
reg [1:0] sclk_sync, cs_sync;
```

The registers `sclk_sync` and `cs_sync` implement **double-flop synchronization** for the external SPI signals (`sclk` and `cs_n`). Even if the SPI master and the internal peripheral operate at similar frequencies, the clocks are not phase-aligned, meaning the incoming signals must be synchronized to the internal `clk` domain to prevent metastability.

Each synchronizer register stores **two bits**, corresponding to the two most recently sampled values of the external signal. They are initialized to:

- `sclk_sync = 2'b00`
- `cs_sync = 2'b11` (since chip select is active-low)

On every `posedge clk`, the new sampled value is appended:

```
sclk_sync <= {sclk_sync[0], sclk};
cs_sync   <= {cs_sync[0], cs_n};
```

This enables detection of **rising edges**, **falling edges**, and **chip-select activation** through simple bit-pattern comparisons.

---

The SPI logic uses a 3-bit register `byte_cnt` to track the number of bits received within the current byte. Since the system processes only **one byte at a time**, this counter asserts completion once all 8 bits have been shifted in.

The module also contains two 8-bit shift registers:

- `shift_in` — stores the data received from MOSI (and is exposed via `data_in`)
- `shift_out` — contains the byte to be transmitted on MISO

```
reg [2:0] byte_cnt;
reg [7:0] shift_in, shift_out;
reg miso_reg;
assign miso = miso_reg;
assign data_in = shift_in;
```

---

### **SPI Timing Logic: `sclk_rising`, `sclk_falling`, and `cs_active`**

The synchronized SPI signals allow the design to derive the following control events:

- **`sclk_rising`** — SCLK transitions from `0` to `1`
- **`sclk_falling`** — SCLK transitions from `1` to `0`
- **`cs_active`** — chip-select is asserted (`cs_n == 0`)

These signals determine when bits are received or transmitted.

---

### **Main State Machine (`always @(posedge clk or negedge rst_n)`)**

On each rising edge of the internal clock (or falling edge of reset):

#### **1. Reset Condition**

If `rst_n == 0`, all internal registers are set to known values:

- `byte_cnt` resets to `0`
- `shift_in` and `shift_out` clear to `0`
- `miso_reg` outputs `0`

#### **2. Idle State (`cs_active == 0`)**

If reset is not asserted and chip-select is inactive:

- The byte counter is cleared.
- The next transmit byte (`data_out`) is loaded into `shift_out`.
- The first bit to be transmitted (`data_out[7]`) is prepared in `miso_reg`.

This stage prepares the slave before the SPI master begins a transfer.

---

### **3. Active SPI Transfer (`cs_active == 1`)**

When a transaction is active, three possible events occur:

#### **1. `sclk_rising` — Receiving a bit on MOSI**

On the rising edge of SCLK:

- `shift_in` shifts left by one bit.
- The newest MOSI bit is inserted as the least significant bit.
- `byte_cnt` increments.

This corresponds to **data reception**.

#### **2. `sclk_falling` — Sending a bit on MISO**

On the falling edge of SCLK:

- `shift_out` shifts left.
- A `0` is inserted as the LSB.
- `shift_out[6]` is copied into `miso_reg`.

This performs **data transmission**.

#### **3. End-of-Byte Handling (when `byte_cnt == 7`)**

On the rising edge when the last bit of the byte has been received:

- `shift_out` is reloaded with the next `data_out`.
- `miso_reg` is updated with the new MSB (`data_out[7]`).

This supports continuous multi-byte transfers.

---

### **Byte Completion Signal (`byte_sync`)**

The final `always` block generates a single-cycle strobe named `byte_sync` using the internal register `byte_sync_reg`.

A pulse is generated when:

- `cs_active == 1`
- `sclk_rising == 1`
- `byte_cnt == 7`

At this moment, the full 8-bit value in `shift_in` is valid and ready for the downstream logic.

This signal is essential for the component that decodes or processes the received SPI byte.

---

### INSTRUCTION DECODER

# Implementation Notes for `regs.v` + `counter.v`

## Register Block Implementation (`regs.v`)

This section describes only the implementation details specific to my design, not the generic architecture already provided in the assignment.

### Internal Structure

All user-visible registers (`PERIOD`, `COUNTER_EN`, `COMPARE1/2`, `PRESCALE`, `UPNOTDOWN`, `PWM_EN`, `FUNCTIONS`) are stored using Verilog `reg` variables with their exact logical width.  
Two additional internal elements are used:

- `count_reset_sh` – a 2-bit internal countdown for generating the two‑cycle active pulse for `COUNTER_RESET`.
- `data_read` – combinational multiplexer output for read operations.

### Addressing Choices

- The module receives a 6-bit address.
- 16-bit registers are split into LSB/MSB across consecutive addresses.
- Unused addresses have no effect on write and return `0x00` on read.

### COUNTER_RESET Mechanism

Writing to address `0x07` loads `count_reset_sh = 2'b11`, which decrements each clock.  
`count_reset` is high whenever the countdown is non‑zero, producing an exact two‑cycle pulse.

### Write Logic Details

Only meaningful bits are stored:

- Single-bit registers (`en`, `upnotdown`, `pwm_en`) use `data_write[0]`
- `FUNCTIONS` uses `data_write[1:0]`
- 16‑bit registers follow LSB/MSB splitting.

### Read Logic Details

The read path is a combinational multiplexer:

- 16‑bit registers return LSB/MSB halves
- Single‑bit registers are zero‑extended
- `COUNTER_RESET` always returns `0x00`
- Invalid addresses return `0x00`

### Reset Behaviour

Registers initialize to deterministic defaults:  
counter disabled, prescaler zero, comparators zero, PWM disabled, up-count direction.

---

## Counter Implementation (`counter.v`)

### Internal State and Prescaler

Two 16‑bit registers:

- `count_val` – main up/down counter
- `presc_cnt` – internal prescaler counter

A combinational wire computes the prescaler target:

```
prescale_target = 1 << prescale;
```

This implements frequency division by `2^PRESCALE`.

### Reset and Enable Behaviour

- Asynchronous reset clears both registers.
- `count_reset` has highest priority and resets only counter-related registers.
- When `en = 0`, `count_val` holds its value while `presc_cnt` resets.

### Prescaler and Counting Logic

If `PRESCALE = 0`, the counter ticks every clock.  
If `PRESCALE > 0`, the prescaler increments until reaching `prescale_target − 1`, then resets and produces one tick.

### Up/Down and Period Handling

On each tick:

- **Up-counting**: increment until reaching `period`, then wrap to `0`
- **Down-counting**: decrement until `0`, then wrap to `period`

`COMPARE1` and `COMPARE2` are not used in this module; they are consumed by the PWM block.
