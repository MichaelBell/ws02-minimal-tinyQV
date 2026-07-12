`default_nettype none

`include "slot_defines.svh"

module tb_top #(
    // Signal pads
    parameter NUM_INPUT_PADS = `NUM_INPUT_PADS,
    parameter NUM_BIDIR_PADS = `NUM_BIDIR_PADS,
    parameter NUM_ANALOG_PADS = `NUM_ANALOG_PADS
)(
    inout [3:0] qspi_data
);

    reg uart_rx;
    wire uart_tx;
    wire uart_rts;

    reg [5:0] ui_in;
    wire [6:0] uio;
    wire [5:0] uo_out;

    wire [NUM_BIDIR_PADS-1:0] bidir_PAD;

    assign bidir_PAD[12:7] = ui_in;
    assign uio[5:4] = qspi_data[3:2];
    assign uio[2:1] = qspi_data[1:0];
    assign bidir_PAD[6:0] = uio;
    assign uo_out = bidir_PAD[12:7];
    assign uart_tx = bidir_PAD[7];
    assign uart_rts = bidir_PAD[10];
    assign bidir_PAD[8] = uart_rx;

    wire clk_PAD;
    wire rst_n_PAD;

`ifdef USE_POWER_PINS
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

    chip_top uut (
`ifdef USE_POWER_PINS
        .VDD(VPWR),
        .VSS(VGND),
`endif

        .clk_PAD(clk_PAD),
        .rst_n_PAD(rst_n_PAD),
        
        .bidir_PAD(bidir_PAD)
    );

endmodule

