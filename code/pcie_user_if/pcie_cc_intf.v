
`timescale 100ps / 1ps

module pcie_cc_intf #(
parameter   DWIDTH  = 256      //256 or 128 or 64
)(
input                           pcie_clk            ,
input                           pcie_rst            ,
input                           pcie_link_up        ,
    // pciecore interface GEN3 for xilinex kintex ultrascale+
output      [DWIDTH-1:0]        s_axis_cc_tdata     ,
output      [32: 0]             s_axis_cc_tuser     ,
output                          s_axis_cc_tlast     ,
output      [DWIDTH/32-1:0]     s_axis_cc_tkeep     ,
output                          s_axis_cc_tvalid    ,
input                           s_axis_cc_tready    ,
    //pcie_cplr_asm interface
input                           user_clk            ,
input                           user_rst            ,
input       [15: 0]             cc_cplr_data_ex     ,
input       [127:0]             cc_cplr_data        ,   //Pcie write operation
input                           cc_cplr_wen         ,
output  reg                     cc_cplr_ready       ,

//output  reg [255:0]             cap_cc_data         ,
//output  reg                     cap_cc_wen          ,
output      [15: 0]             odbg_info

);

localparam  U_DLY       = 1 ;


//数据结构
/*******************************************************************************************
    request request 接收接口处理，仅支持DWord aligned模式、不支持TPH、parity
    不使能discontinue，不支持rq与cc间的保序
    rdata数据格式：其中first_be、last_be仅在第一拍有效,mod为实际有效字节个数
    |287:280|279|278|277:270|269: 266|265:262|261|260:256|255:0|
    |rsv    |sop|eop|keep   |first_be|last_be|err|mod    |data |
    data扩展位
    |31 |30 :  24|23 |22 |21:14|13  : 10|9  :  6| 5 |4:0|
    |end|sequence|sop|eop|keep |first_be|last_be|err|mod|
********************************************************************************************/
localparam  SOP         = 15 ;
localparam  EOP         = 14 ;
localparam  ERR         = 13 ;
localparam  KEEP_M      = 12 ;
localparam  KEEP_L      = 8  ;
localparam  FBE_M       = 7  ;
localparam  FBE_L       = 4  ;
localparam  LBE_M       = 3  ;
localparam  LBE_L       = 0  ;



wire    [143:0]             cc_cplr_din             ;
reg     [143:0]             cc_cplr_din_1d          ;
reg                         cc_cplr_wen_1d          ;
wire    [143:0]             cc_cplr_dout            ;
wire    [ 5: 0]             cc_cplr_usedw           ;
wire                        cc_cplr_ren             ;
wire    [15: 0]             cc_cplr_q_ex            ;
wire    [127:0]             cc_cplr_q               ;
wire                        cc_cplr_empty           ;


wire                        discontinue             ;

assign odbg_info = {12'b0,
                    1'b0,cc_cplr_empty,cc_cplr_ready,s_axis_cc_tready};
//  Stage 2
//================================================
//  poll read and write command
//================================================


assign cc_cplr_din = {cc_cplr_data_ex,cc_cplr_data};
always@(posedge user_clk)
begin
    cc_cplr_din_1d <= cc_cplr_din;
    cc_cplr_wen_1d <= cc_cplr_wen;
end

assign cc_cplr_q_ex = cc_cplr_dout[143:128];
assign cc_cplr_q    = cc_cplr_dout[127:0];

always @ ( posedge user_clk )
    cc_cplr_ready <= #U_DLY (cc_cplr_usedw[5:4]>=2'd1)? 1'b0 : 1'b1 ;

async_fifo #(
    .DATA_WIDTH     ( 144           ),
    .DEPTH_WIDTH    ( 5             ),
    .MEMORY_TYPE    ( "distributed" )
)
u_oper_fifo(
    .rst            ( pcie_rst      ),
    .wr_clk         ( user_clk      ),
    .rd_clk         ( pcie_clk      ),
    .din            ( cc_cplr_din_1d),
    .wr_en          ( cc_cplr_wen_1d),
    .rd_en          ( cc_cplr_ren   ),
    .dout           ( cc_cplr_dout  ),
    .full           ( ),
    .empty          ( cc_cplr_empty ),
    .alempty        ( ),
    .wr_data_count  ( cc_cplr_usedw ),
    .wr_rst_busy    ( ),
    .rd_rst_busy    ( )
);



//  Stage 2
//================================================
//  poll read and write command
//================================================

//===========================================================================
//  TX data transmit
//===========================================================================
//always@(posedge pcie_clk )
//begin
//    if ( pcie_rst )
//        poll_id <= #U_DLY 2'b0;
//    else
//    begin
//        if ( cc_oper_ren & cc_oper_q_ex[EOP] )  //写操作完成时，如果有待操作的读指令，且有tag时，切换到读操作
//            poll_id <= #U_DLY (poll_id>=CHAN-1)? 2'b0 : poll_id + 1'b1;
//        else if ( ~state & cc_oper_empty)
//            poll_id <= #U_DLY (poll_id>=CHAN-1)? 2'b0 : poll_id + 1'b1;
//        else
//            ;
//    end
//end



////用于通道切换的状态判断
//always@(posedge pcie_clk )
//begin
//    if ( pcie_rst )
//        state <= #U_DLY 1'b0;
//    else
//    begin
//        case(state)
//        1'b0    :   if ( ~cc_oper_empty )
//                        state <= #U_DLY 1'b1;
//                    else
//                        state <= #U_DLY 1'b0;
//        1'b1    :   if ( cc_oper_ren & cc_oper_q_ex[EOP] )
//                        state <= #U_DLY 1'b0;
//                    else
//                        state <= #U_DLY 1'b1;
//        default :   state <= #U_DLY 1'b0;
//        endcase
//    end
//end

//assign cc_oper_ren = ~cc_oper_empty & state & ~opt_full;
assign cc_cplr_ren = ~cc_cplr_empty & s_axis_cc_tready;




assign s_axis_cc_tvalid     = ~cc_cplr_empty ;

    //产生tkeep信号，仅在最后一拍有效，为改善时序，由前级模块完成计算
generate if(DWIDTH==256)
    assign s_axis_cc_tkeep  = 8'h0f;
else if(DWIDTH==128)
    assign s_axis_cc_tkeep  = 4'hf;
endgenerate
    //tlast结束标志
assign s_axis_cc_tlast      = cc_cplr_q_ex[EOP];
    //s_axis_rq_tdata完成DW顺序调整
assign s_axis_cc_tdata      = {384'b0,cc_cplr_q};

assign discontinue          = cc_cplr_q_ex[ERR];
    //不支持TPH特性，不使能基于byte的odd parity
assign s_axis_cc_tuser      = { 32'h0,discontinue};



//always@(posedge pcie_clk)
//begin
//    if(s_axis_cc_tvalid & s_axis_cc_tready)
//    begin
//        cap_cc_data <= #U_DLY s_axis_cc_tdata;
//        cap_cc_wen  <= #U_DLY 1'b1;
//    end
//    else
//        cap_cc_wen <= #U_DLY 1'b0;
//end


endmodule




