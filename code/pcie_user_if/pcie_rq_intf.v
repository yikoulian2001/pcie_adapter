
`timescale 100ps / 1ps

module pcie_rq_intf #(
parameter   DWIDTH  = 256      //256 or 128 or 64
)(
input                       pcie_clk            ,
input                       pcie_rst            ,
input                       pcie_link_up        ,
    // pciecore interface GEN3 for xilinex kintex ultrascale+
output                      s_axis_rq_tlast     ,
output      [DWIDTH-1:0]    s_axis_rq_tdata     ,
output      [61: 0]         s_axis_rq_tuser     ,
output      [DWIDTH/32-1:0] s_axis_rq_tkeep     ,
input                       s_axis_rq_tready    ,
output                      s_axis_rq_tvalid    ,
    //system signal
input                       user_clk            ,
input                       user_rst            ,
input       [15: 0]         rq_oper_data_ex     ,
input       [DWIDTH-1:0]    rq_oper_data        ,
input                       rq_oper_wen         ,
output  reg                 rq_oper_ready       ,

//output  reg [255:0]         cap_rq_data         ,
//output  reg                 cap_rq_wen          ,
output      [15: 0]         odbg_info

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
localparam  KEEP_M      = 11 ;
localparam  KEEP_L      = 8  ;
localparam  FBE_M       = 7  ;
localparam  FBE_L       = 4  ;
localparam  LBE_M       = 3  ;
localparam  LBE_L       = 0  ;





//  pollrx_data interface
wire    [DWIDTH+15:0]   rq_oper_din             ;
reg     [DWIDTH+15:0]   rq_oper_din_1d          ;
reg                     rq_oper_wen_1d          ;
wire    [DWIDTH+15:0]   rq_oper_dout            ;
wire                    rq_oper_hwen            ;
wire    [ 5: 0]         rq_oper_husedw          ;
wire                    rq_oper_hempty          ;
wire                    rq_oper_hfull           ;
wire                    rq_oper_hren            ;
wire    [ 6: 0]         rq_oper_dusedw          ;
wire                    rq_oper_ren             ;
wire                    rq_oper_dempty          ;
wire                    rq_oper_dfull           ;
wire    [15: 0]         rq_oper_q_ex            ;
wire    [DWIDTH-1:0]    rq_oper_q               ;
wire                    rq_oper_empty           ;


wire    [ 3: 0]         rq_tuser_first_be       ;
wire    [ 3: 0]         rq_tuser_last_be        ;
wire                    discontinue             ;

reg     rq_idle;

reg                     dfull_flg       ;
reg     [ 3: 0]         dfull_cnt       ;
reg                     hfull_flg       ;
reg     [ 3: 0]         hfull_cnt       ;

//generate if( ORDER_MODE == "Strict" ) begin : gen_dbg
//    assign odbg_info = {1'b0,last_seq,1'b0,seq_init,seq_done,seq_vld,poll_id,s_axis_rq_tready,state};
//end else if( ORDER_MODE == "Relax" ) begin
////    assign odbg_info = {rq_idle,read_enable,2'b0,
////                        pcie_tfc_nph_av,pcie_tfc_npd_av,
////                        4'b0,
////                        1'b0,poll_id,s_axis_rq_tready,state};
    assign odbg_info = {rq_idle,1'b0,hfull_flg,dfull_flg,
                        hfull_cnt,
                        dfull_cnt,
                        rq_oper_hempty,rq_oper_empty,rq_oper_ready,s_axis_rq_tready};
//end
//endgenerate

always@(posedge user_clk)
begin
    if(user_rst)
    begin
        dfull_flg <= 1'b0;
        dfull_cnt <= 4'b0;
    end
    else if(rq_oper_wen_1d & rq_oper_dfull)
    begin
        dfull_flg <= 1'b1;
        dfull_cnt <= dfull_cnt + 1'b1;
    end
    else
        ;
end
always@(posedge user_clk)
begin
    if(user_rst)
    begin
        hfull_flg <= 1'b0;
        hfull_cnt <= 4'b0;
    end
    else if(rq_oper_hwen & rq_oper_hfull)
    begin
        hfull_flg <= 1'b1;
        hfull_cnt <= hfull_cnt + 1'b1;
    end
    else
        ;
end

always@(posedge pcie_clk)
    rq_idle <= s_axis_rq_tready & ~s_axis_rq_tvalid;
//======================================================================================================================================================
//
//  PCIE x8 Gen3 interface used for transmit Data, Read Command and receive Data etc.
//
//======================================================================================================================================================
//  Stage 1 (store the operation data)
//================================================
//  Write Command/Data and Read Command
//================================================


//write side
assign rq_oper_din = {rq_oper_data_ex,rq_oper_data};
always@(posedge user_clk)
begin
    rq_oper_din_1d <= rq_oper_din;
    rq_oper_wen_1d <= rq_oper_wen;
end

assign rq_oper_q_ex = rq_oper_dout[DWIDTH+:16];
assign rq_oper_q    = rq_oper_dout[0+:DWIDTH];


assign rq_oper_hwen = rq_oper_din_1d[DWIDTH+EOP] & rq_oper_wen_1d;
assign rq_oper_hren = rq_oper_q_ex[EOP] & rq_oper_ren;

always @ ( posedge user_clk )
    rq_oper_ready <= #U_DLY (rq_oper_dusedw[6:4]>=3'h3 || rq_oper_husedw[5:3]>=3'h3)? 1'b0 : 1'b1 ;

async_fifo #(
    .DATA_WIDTH     ( 1             ),
    .DEPTH_WIDTH    ( 5             ),
    .MEMORY_TYPE    ( "distributed" )
)
u_oper_head(
    .rst            ( pcie_rst          ),
    .wr_clk         ( user_clk          ),
    .rd_clk         ( pcie_clk          ),
    .din            ( 1'b0              ),
    .wr_en          ( rq_oper_hwen      ),
    .rd_en          ( rq_oper_hren      ),
    .dout           ( ),
    .full           ( rq_oper_hfull     ),
    .empty          ( rq_oper_hempty    ),
    .alempty        ( ),
    .wr_data_count  ( rq_oper_husedw    ),
    .wr_rst_busy    ( ),
    .rd_rst_busy    ( )
);
async_fifo #(
    .DATA_WIDTH     ( DWIDTH+16     ),
    .DEPTH_WIDTH    ( 6             ),
    .MEMORY_TYPE    ( "distributed" )
)
u_oper_data(
    .rst            ( pcie_rst          ),
    .wr_clk         ( user_clk          ),
    .rd_clk         ( pcie_clk          ),
    .din            ( rq_oper_din_1d    ),
    .wr_en          ( rq_oper_wen_1d    ),
    .rd_en          ( rq_oper_ren       ),
    .dout           ( rq_oper_dout      ),
    .full           ( rq_oper_dfull     ),
    .empty          ( rq_oper_dempty    ),
    .alempty        ( ),
    .wr_data_count  ( rq_oper_dusedw    ),
    .wr_rst_busy    ( ),
    .rd_rst_busy    ( )
);


assign rq_oper_empty = rq_oper_dempty | rq_oper_hempty;




//  Stage 2
//================================================
//  poll read and write command
//================================================

assign rq_oper_ren = ~rq_oper_empty & s_axis_rq_tready;


assign s_axis_rq_tvalid     = ~rq_oper_empty;

    //产生tkeep信号，仅在最后一拍有效，为改善时序，由前级模块完成计算
generate if(DWIDTH==256)
    assign s_axis_rq_tkeep  = (~rq_oper_q_ex[EOP])?            8'hff :
                              (rq_oper_q_ex[KEEP_L+:3]==3'd0)? 8'h01 :
                              (rq_oper_q_ex[KEEP_L+:3]==3'd1)? 8'h03 :
                              (rq_oper_q_ex[KEEP_L+:3]==3'd2)? 8'h07 :
                              (rq_oper_q_ex[KEEP_L+:3]==3'd3)? 8'h0f :
                              (rq_oper_q_ex[KEEP_L+:3]==3'd4)? 8'h1f :
                              (rq_oper_q_ex[KEEP_L+:3]==3'd5)? 8'h3f :
                              (rq_oper_q_ex[KEEP_L+:3]==3'd6)? 8'h7f :
                                                               8'hff;
else if(DWIDTH==128)
    assign s_axis_rq_tkeep  = (~rq_oper_q_ex[EOP])?            4'hf :
                              (rq_oper_q_ex[KEEP_L+:2]==2'd0)? 4'h1 :
                              (rq_oper_q_ex[KEEP_L+:2]==2'd1)? 4'h3 :
                              (rq_oper_q_ex[KEEP_L+:2]==2'd2)? 4'h7 :
                                                               4'hf;
endgenerate

    //tlast结束标志
assign s_axis_rq_tlast      = rq_oper_q_ex[EOP];
    //s_axis_rq_tdata完成DW顺序调整
assign s_axis_rq_tdata      = rq_oper_q;
    //填充first_be及last_be
assign rq_tuser_first_be    = rq_oper_q_ex[FBE_M:FBE_L];
assign rq_tuser_last_be     = rq_oper_q_ex[LBE_M:LBE_L];

assign discontinue = rq_oper_q_ex[ERR];
    //不支持TPH特性，不使能基于byte的odd parity
assign s_axis_rq_tuser      = { 50'h0,discontinue,3'b0, rq_tuser_last_be, rq_tuser_first_be };




//always@(posedge pcie_clk)
//begin
//    if(s_axis_rq_tvalid & s_axis_rq_tready)
//    begin
//        cap_rq_data <= #U_DLY s_axis_rq_tdata;                                                                                              //write
//        cap_rq_wen  <= #U_DLY 1'b1;
//    end
//    else
//        cap_rq_wen  <= #U_DLY 1'b0;
//end

endmodule




