/*
 * Copyright (c) 2026 Michael Bell
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

localparam BIT_SAMPLES = 'd4;

module tqvp_usb_cdc #(
    parameter NUM_GPIO = 8
    ) (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [NUM_GPIO-1:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                         // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [NUM_GPIO-1:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                         // Note that uo_out[0] is normally used for UART TX.

    output usb_tx_en,

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    output        user_interrupt  // Dedicated interrupt request for this peripheral
);

    wire  usb_dp_in = ui_in[3];
    wire  usb_dn_in = ui_in[4];

    wire usb_dp_out;
    wire usb_dn_out;
    wire usb_pu_out;

    assign uo_out[2:0] = '0;
    assign uo_out[3] = usb_dp_out;
    assign uo_out[4] = usb_dn_out;
    assign uo_out[5] = usb_pu_out;

    wire [7:0] uart_rx_byte;
    wire       uart_rx_valid;

    wire       usb_in_ready;
    wire       configured;

    // Buffer one byte of received data
    reg uart_rx_buffered;
    reg [7:0] uart_rx_buf_data;

    always @(posedge clk) begin
        if (!rst_n) begin
            uart_rx_buffered <= 0;
        end else begin
            if (uart_rx_buffered == 0) begin
                uart_rx_buffered <= uart_rx_valid;
                uart_rx_buf_data <= uart_rx_byte;
            end else begin
                if (address == 6'h0 && data_read_n != 2'b11) begin
                    uart_rx_buffered <= 0;
                end
            end
        end
    end

    // Interrupt on byte available
    assign user_interrupt = uart_rx_buffered;
    assign data_out = address == 6'h0 ? {24'd0, uart_rx_buf_data} :
                      address == 6'h4 ? {29'd0, configured, uart_rx_buffered, ~usb_in_ready} : 32'd0;
    assign data_ready = 1;    

  /* USB Serial */
  usb_cdc #(
      .VENDORID              (16'h0000), // TODO: Get a PID
      .PRODUCTID             (16'h0000),             // https://pid.codes/1209/5454/
      .IN_BULK_MAXPACKETSIZE ('d8),
      .OUT_BULK_MAXPACKETSIZE('d8),
      .BIT_SAMPLES           (BIT_SAMPLES),
      .USE_APP_CLK           (0),
      .APP_CLK_RATIO         (BIT_SAMPLES * 12 / 2)  // BIT_SAMPLES * 12MHz / 2MHz
  ) u_usb_cdc (
      .frame_o(),
      .configured_o(configured),

      .app_clk_i(clk),
      .clk_i(clk),
      .rstn_i(rst_n),
      .out_ready_i(~uart_rx_buffered),
      .in_data_i(data_in[7:0]),
      .in_valid_i(data_write_n != 2'b11 && address == 6'h0),
      .dp_rx_i(usb_dp_in),
      .dn_rx_i(usb_dn_in),

      .out_data_o(uart_rx_byte),
      .out_valid_o(uart_rx_valid),
      .in_ready_o(usb_in_ready),
      .dp_pu_o(usb_pu_out),
      .tx_en_o(usb_tx_en),
      .dp_tx_o(usb_dp_out),
      .dn_tx_o(usb_dn_out)
  );

  wire _unused = &{data_in[31:8], ui_in[NUM_GPIO-1:5], ui_in[2:0], 1'b0};

endmodule
