/*
*****************************
* MODULE : serial_fpga
*
* This module implements a bridge between
* a RS232 serial interface and the
* HomeBrew Automation Bus (HBA).  It allows an
* external processor like a Raspberry Pi
* control the FPGA peripherals on the HBA Bus.
*
* Status: In development
*
* Author : Brandon Blodget
* Create Date: 05/02/2019
*
*****************************
*/

/*
*****************************
*
* Copyright (C) 2019 by Brandon Blodget <brandon.blodget@gmail.com>
* All rights reserved.
*
* License:
*
* This program is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.
*
*****************************
*/

// Force error when implicit net has no type.
`default_nettype none

module serial_fpga #
(
    parameter integer CLK_FREQUENCY = 50_000_000,
    parameter integer BAUD = 32'd115_200,

    parameter integer DBUS_WIDTH = 8,
    parameter integer PERIPH_ADDR_WIDTH = 4,
    parameter integer REG_ADDR_WIDTH = 8,
    parameter integer PERIPH_ADDR = 0,
    // Default ADDR_WIDTH = 12
    parameter integer ADDR_WIDTH = PERIPH_ADDR_WIDTH + REG_ADDR_WIDTH
)
(
    // Serial Interface
    input wire  io_rxd,
    output wire io_txd,
    output reg  io_intr,

    // Interrupts  from slave
    input wire [15:0] slave_interrupt,

    // HBA Bus Slave Interface
    input wire hba_clk,
    input wire hba_reset,
    input wire hba_rnw,         // 1=Read from register. 0=Write to register.
    input wire hba_select,      // Transfer in progress.
    input wire [ADDR_WIDTH-1:0] hba_abus, // The input address bus.
    input wire [DBUS_WIDTH-1:0] hba_dbus,  // The input data bus.

    output wire [DBUS_WIDTH-1:0] hba_dbus_slave,   // The output data bus.
    output wire hba_xferack_slave,     // Acknowledge transfer requested. 
                                    // Asserted when request has been completed. 
                                    // Must be zero when inactive.

    // HBA Bus Master Interface
    // XXX input wire hba_clk,
    // XXX input wire hba_reset,
    input wire hba_xferack,  // Asserted when request has been completed.
    input wire hba_mgrant,   // Master access has be granted.
    output wire hba_mrequest,     // Requests access to the bus.
    output wire [ADDR_WIDTH-1:0] hba_abus_master,  // The target address. Must be zero when inactive.
    output wire hba_rnw_master,          // 1=Read from register. 0=Write to register.
    output wire hba_select_master,       // Transfer in progress
    output wire [DBUS_WIDTH-1:0] hba_dbus_master    // The write data bus.

);

/*
****************************
* Signals
****************************
*/

wire uart0_rd;
wire uart0_wr;
wire [7:0] tx_data;

wire rx_valid;
wire tx_busy;
wire [7:0] rx_data;

// App hba_master interface
reg [PERIPH_ADDR_WIDTH-1:0] app_core_addr;
reg [REG_ADDR_WIDTH-1:0] app_reg_addr;
reg [DBUS_WIDTH-1:0] app_data_in;
reg app_rnw;
reg app_en_strobe;    // rising edge start state machine
wire [DBUS_WIDTH-1:0] app_data_out;
wire app_valid_out;    // read or write transfer complete. Assert one clock cycle.

// send_recv UI
reg [7:0] serial_tx_data;
reg serial_wr;
reg serial_rd;
wire serial_valid;
wire [7:0] serial_rx_data;

// HBA Slave registers
reg slv_wr_en;

// slave_interrupt[7:0]
wire [DBUS_WIDTH-1:0] reg_intr0;
reg [DBUS_WIDTH-1:0] reg_intr0_in;

// slave_interrupt[15:8]
wire [DBUS_WIDTH-1:0] reg_intr1;
reg [DBUS_WIDTH-1:0] reg_intr1_in;

wire [DBUS_WIDTH-1:0] reg_rate_ms;

/*
****************************
* Instantiations
****************************
*/

buart # (
    .CLKFREQ(CLK_FREQUENCY)
) uart_inst (
    // inputs
   .clk(hba_clk),
   .resetq(~hba_reset),
   .baud(BAUD),    // [31:0] max = 32'd921600
   .rx(io_rxd),            // recv wire
   .rd(uart0_rd),    // read strobe
   .wr(uart0_wr),   // write strobe
   .tx_data(tx_data),   // [7:0]

   // outputs
   .tx(io_txd),           // xmit wire
   .valid(rx_valid),   // has recv data 
   .busy(tx_busy),     // is transmitting
   .rx_data(rx_data)   // [7:0]
);

send_recv send_recv_inst
(
    .clk(hba_clk),
    .reset(hba_reset),

    // control interface
    .serial_tx_data(serial_tx_data), // [7:0]
    .serial_wr(serial_wr),
    .serial_rd(serial_rd),
    .serial_valid(serial_valid),
    .serial_rx_data(serial_rx_data),

    // TX uart interface
    .tx_data(tx_data), // [7:0]
    .tx_wr_strobe(uart0_wr),
    .tx_busy(tx_busy),

    // RX uart interface
    .rx_data(rx_data), // [7:0]
    .rx_valid(rx_valid),
    .rx_rd_strobe(uart0_rd)
);

hba_master #
(
    .DBUS_WIDTH(DBUS_WIDTH),
    .PERIPH_ADDR_WIDTH(PERIPH_ADDR_WIDTH),
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH)
) hba_master_inst
(
    // App interface
    .app_core_addr(app_core_addr),
    .app_reg_addr(app_reg_addr),
    .app_data_in(app_data_in),
    .app_rnw(app_rnw),
    .app_en_strobe(app_en_strobe),  // rising edge start state machine
    .app_data_out(app_data_out),
    .app_valid_out(app_valid_out),  // read or write transfer complete. Assert one clock cycle.

    // HBA Bus Master Interface
    .hba_clk(hba_clk),
    .hba_reset(hba_reset),
    .hba_mgrant(hba_mgrant),   // Master access has be granted.
    .hba_xferack(hba_xferack),  // Asserted when request has been completed.
    .hba_dbus(hba_dbus),       // The read data bus.
    .hba_mrequest(hba_mrequest),     // Requests access to the bus.
    .hba_abus_master(hba_abus_master),  // The target address. Must be zero when inactive.
    .hba_rnw_master(hba_rnw_master),         // 1=Read from register. 0=Write to register.
    .hba_select_master(hba_select_master),      // Transfer in progress
    .hba_dbus_master(hba_dbus_master)    // The write data bus.
);

hba_reg_bank #
(
    .DBUS_WIDTH(DBUS_WIDTH),
    .PERIPH_ADDR_WIDTH(PERIPH_ADDR_WIDTH),
    .REG_ADDR_WIDTH(REG_ADDR_WIDTH),
    .PERIPH_ADDR(PERIPH_ADDR)
) hba_reg_bank_inst
(
    // HBA Bus Slave Interface
    .hba_clk(hba_clk),
    .hba_reset(hba_reset),
    .hba_rnw(hba_rnw),         // 1=Read from register. 0=Write to register.
    .hba_select(hba_select),      // Transfer in progress.
    .hba_abus(hba_abus), // The input address bus.
    .hba_dbus(hba_dbus),  // The input data bus.

    .hba_dbus_slave(hba_dbus_slave),   // The output data bus.
    .hba_xferack_slave(hba_xferack_slave),     // Acknowledge transfer requested. 
                                    // Asserted when request has been completed. 
                                    // Must be zero when inactive.

    // Access to registgers
    .slv_reg0(reg_intr0),        // read access
    .slv_reg0_in(reg_intr0_in),  // write access

    .slv_reg1(reg_intr1),        // read access
    .slv_reg1_in(reg_intr1_in),  // write access

    .slv_reg2(reg_rate_ms),        // Max interrupt rate.

    .slv_wr_en(slv_wr_en),     // No write.
    .slv_wr_mask(4'b011),   // 0011, Enable writes to slv_reg0, and slv_reg1.
    .slv_autoclr_mask(4'b011)   // 0011, Enable clearing when read
);


/*
****************************
* Main
****************************
*/

// Serial Interface State Machine.
reg [3:0] serial_state;

reg [7:0] cmd_byte;
reg [7:0] regaddr_byte;
reg [3:0] transfer_num;

wire rnw_bit;
wire [2:0] num_bytes_bits;
wire [3:0] core_addr_bits;

assign rnw_bit = cmd_byte[7];
assign num_bytes_bits = cmd_byte[6:4];
assign core_addr_bits = cmd_byte[3:0];

// States
localparam IDLE                     = 0;
localparam REG_ADDR                 = 1;
localparam ECHO_CMD                 = 2;
localparam ECHO_RAD                 = 3;
localparam HBA_SETUP                = 4;
localparam HBA_SERIAL_READ          = 5;
localparam HBA_WAIT                 = 6;
localparam HBA_WAIT2                = 7;
localparam ACK                      = 8;
localparam DONE                     = 9;

// rnw values
localparam RPI_WRITE            = 0;
localparam RPI_READ             = 1;

// ACK constant
localparam ACK_CHAR         =8'hAC;
localparam NACK_CHAR        =8'h56;

always @ (posedge hba_clk)
begin
    if (hba_reset) begin
        serial_state <= IDLE;
        cmd_byte <= 0;
        regaddr_byte <= 0;
        transfer_num <= 0;

        app_core_addr <= 0;
        app_reg_addr <= 0;
        app_data_in <= 0;
        app_rnw <= 0;
        app_en_strobe <= 0;

        serial_tx_data <= 0;
        serial_wr <= 0;
        serial_rd <= 0;

    end else begin
        case (serial_state)
            IDLE : begin
                serial_wr <= 0;
                transfer_num <= 0;
                app_en_strobe <= 0;

                // Read the cmd_byte
                serial_rd <= 1;
                if (serial_valid) begin
                    serial_rd <= 0;
                    cmd_byte <= serial_rx_data;
                    serial_state <= REG_ADDR;
                end
            end
            REG_ADDR : begin
                // Read the regAddr byte
                serial_rd <= 1;
                if (serial_valid) begin
                    serial_rd <= 0;
                    transfer_num <= num_bytes_bits + 1;
                    regaddr_byte <= serial_rx_data;
                    if (rnw_bit == RPI_READ) begin
                        serial_state <= ECHO_CMD;
                    end else begin
                        serial_state <= HBA_SETUP;
                    end
                end
            end
            ECHO_CMD : begin
                // Echo back the command
                serial_tx_data <= cmd_byte;
                serial_wr <= 1;
                if (serial_valid) begin
                    serial_wr <= 0;
                    serial_state <= ECHO_RAD;
                end
            end
            ECHO_RAD : begin
                // Echo back the Reg ADdr
                serial_tx_data <= regaddr_byte;
                serial_wr <= 1;
                if (serial_valid) begin
                    serial_wr <= 0;
                    serial_state <= HBA_SETUP;
                end
            end
            HBA_SETUP : begin
                serial_wr <= 0;
                // XXX serial_rd <= 0;
                app_en_strobe <= 0;

                // Done with Transfer?
                if (transfer_num == 0) begin
                    if (rnw_bit == RPI_READ) begin
                        serial_state <= DONE;
                    end else begin
                        // Send ACK for a write
                        serial_state <= ACK;
                    end
                end else begin
                    // Dec the transfer_num
                    transfer_num <= transfer_num - 1;

                    // Setup the hba_master core
                    app_core_addr <= core_addr_bits;
                    app_reg_addr <= regaddr_byte;
                    app_rnw <= rnw_bit;

                    // Auto increment the register address
                    regaddr_byte <= regaddr_byte + 1;

                    // Serial Op
                    if (rnw_bit == RPI_WRITE) begin
                        // read from serial, then write to hba
                        serial_rd <= 1;
                        serial_state <= HBA_SERIAL_READ;
                    end else begin
                        // read from hba, then write to serial
                        app_en_strobe <= 1;
                        serial_state <= HBA_WAIT;
                    end
                end

            end
            HBA_SERIAL_READ : begin
                if (serial_valid) begin
                    serial_rd <= 0;
                    app_data_in <= serial_rx_data;
                    app_en_strobe <= 1;
                    serial_state <= HBA_WAIT;
                end
            end
            HBA_WAIT : begin
                app_en_strobe <= 0;
                // Wait for hba bus to finish
                if (app_valid_out) begin
                    if (rnw_bit == RPI_WRITE) begin
                        serial_state <= HBA_SETUP;
                    end else begin
                        // Send read data over serial
                        serial_tx_data <= app_data_out;
                        serial_wr <= 1;
                        serial_state <= HBA_WAIT2;
                    end
                end
            end
            HBA_WAIT2 : begin
                if (serial_valid) begin
                    serial_wr <= 0;
                    serial_state <= HBA_SETUP;
                end
            end
            ACK : begin
                serial_tx_data <= ACK_CHAR;
                serial_wr <= 1;
                if (serial_valid) begin
                    serial_wr <= 0;
                    serial_state <= DONE;
                end
            end
            DONE : begin
                if (!serial_valid) begin
                    serial_state <= IDLE;
                end
            end
            default : begin
                serial_state <= IDLE;
            end
        endcase
    end
end

// Generate the interrupt enable at specified rate
localparam ONE_MS_COUNT = ( CLK_FREQUENCY / 1000 );
localparam COUNT_BITS = $clog2(ONE_MS_COUNT);
reg [COUNT_BITS-1:0] count_to_1ms;
reg [7:0] count_1ms;
reg io_intr_en;
always @ (posedge hba_clk)
begin
    if (hba_reset) begin
        count_to_1ms <= 0;
        count_1ms <= 0;
        io_intr_en <= 0;
    end else begin
        io_intr_en <= 0;
        count_to_1ms <= count_to_1ms + 1;
        if (count_to_1ms == (ONE_MS_COUNT-1)) begin
            count_to_1ms <= 0;
            count_1ms <= count_1ms + 1;
        end
        if (count_1ms == reg_rate_ms) begin
            count_1ms <= 0;
            io_intr_en <= 1;
        end
    end
end

// Set the HBA interrupt registers
integer i;
always @ (posedge hba_clk)
begin
    if (hba_reset) begin
        slv_wr_en <= 0;
        reg_intr0_in <= 0;
        reg_intr1_in <= 0;
        io_intr <= 0;
    end else begin
        // Generate interrupt to CPU if any interrupt bits are set
        if (io_intr == 0) begin
            if (io_intr_en) begin
                io_intr <= (|reg_intr0) | (|reg_intr1);
            end
        end else begin
            // if io_intr is 1 then let the clear happen.
            io_intr <= (|reg_intr0) | (|reg_intr1);
        end

        // default
        slv_wr_en <= 0;

        for (i=0; i <8; i=i+1)
        begin
            if (slave_interrupt[i]) begin
                reg_intr0_in[i] <= 1'b1;
                slv_wr_en <= 1;
            end
            if (slave_interrupt[i+8]) begin
                reg_intr1_in[i] <= 1'b1;
                slv_wr_en <= 1;
            end
        end
    end
end

endmodule

