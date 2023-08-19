
`timescale 100ps / 1ps

module pcie_rc_intf #(
parameter   DWIDTH  = 256     //256 or 128 or 64
)(
input                       pcie_clk            ,
input                       pcie_rst            ,
input                       pcie_link_up        ,
    // pciecore interface GEN3 for xilinex virtex7
input       [DWIDTH-1:0]    m_axis_rc_tdata     ,
input       [74: 0]         m_axis_rc_tuser     ,
input                       m_axis_rc_tlast     ,
input       [DWIDTH/32-1:0] m_axis_rc_tkeep     ,
input                       m_axis_rc_tvalid    ,
output  reg                 m_axis_rc_tready    ,
    //pcie_cplr_asm interface
output  reg [15: 0]         rc_cplr_data_ex     ,
output  reg [DWIDTH-1:0]    rc_cplr_data        ,   //Pcie write operation
output  reg                 rc_cplr_wen         ,
input                       rc_cplr_ready       ,

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

    //rc接收接口
wire    [31: 0]         rc_tuser_byte_en    ;
wire                    rc_tuser_is_sof0    ;
wire                    rc_tuser_is_sof1    ;
wire    [ 3: 0]         rc_tuser_is_eof0    ;
wire    [ 3: 0]         rc_tuser_is_eof1    ;
wire                    rc_tuser_discontinue;
wire    [31: 0]         rc_tuser_parity     ;

//reg     [ 7: 0]         tag                 ;


assign odbg_info = {14'b0,rc_cplr_ready,m_axis_rc_tready};
//  Stage 2
//================================================
//  poll read and write command
//================================================

assign  rc_tuser_byte_en        = m_axis_rc_tuser[31:0];
assign  rc_tuser_is_sof0        = m_axis_rc_tuser[32];
assign  rc_tuser_is_sof1        = m_axis_rc_tuser[33];
assign  rc_tuser_is_eof0        = m_axis_rc_tuser[37:34];
assign  rc_tuser_is_eof1        = m_axis_rc_tuser[41:38];
assign  rc_tuser_discontinue    = m_axis_rc_tuser[42];
assign  rc_tuser_parity         = m_axis_rc_tuser[74:43];

/*******************************************************************************************
    request completer 接收接口处理，仅支持DWord aligned模式、NON-straddled模式
********************************************************************************************/


    //m_axis_rc_tvalid有效过程中，即使将满，也不反压ipcore
always @ ( posedge pcie_clk )
    m_axis_rc_tready <= rc_cplr_ready;

//always @ ( posedge pcie_clk )
//begin
//    if( pcie_rst )
//        tag <= #U_DLY 8'b0;
//    else if( rc_tuser_is_sof0 & m_axis_rc_tvalid & m_axis_rc_tready )
//        tag <= #U_DLY m_axis_rc_tdata[71:64];
//    else
//        ;
//end
generate if(DWIDTH==256)
    always @ ( posedge pcie_clk )
    begin
        if(m_axis_rc_tvalid & m_axis_rc_tready)
        begin
            rc_cplr_data_ex[15]    <= #U_DLY rc_tuser_is_sof0;
            rc_cplr_data_ex[14]    <= #U_DLY m_axis_rc_tlast;
            rc_cplr_data_ex[13]    <= #U_DLY rc_tuser_discontinue;
            rc_cplr_data_ex[12:11] <= #U_DLY 2'b0;
            casex( m_axis_rc_tkeep )
            8'b0000_0001 : rc_cplr_data_ex[10:8] <= #U_DLY 3'd0;
            8'b0000_001? : rc_cplr_data_ex[10:8] <= #U_DLY 3'd1;
            8'b0000_01?? : rc_cplr_data_ex[10:8] <= #U_DLY 3'd2;
            8'b0000_1??? : rc_cplr_data_ex[10:8] <= #U_DLY 3'd3;
            8'b0001_???? : rc_cplr_data_ex[10:8] <= #U_DLY 3'd4;
            8'b001?_???? : rc_cplr_data_ex[10:8] <= #U_DLY 3'd5;
            8'b01??_???? : rc_cplr_data_ex[10:8] <= #U_DLY 3'd6;
            default      : rc_cplr_data_ex[10:8] <= #U_DLY 3'd7;
            endcase
            rc_cplr_data_ex[7:4]   <= #U_DLY 4'b0;
            rc_cplr_data_ex[3:0]   <= #U_DLY 4'b0;
        end
        else
            ;
    end
else if(DWIDTH==128)
    always @ ( posedge pcie_clk )
    begin
        if(m_axis_rc_tvalid & m_axis_rc_tready)
        begin
            rc_cplr_data_ex[15]    <= #U_DLY rc_tuser_is_sof0;
            rc_cplr_data_ex[14]    <= #U_DLY m_axis_rc_tlast;
            rc_cplr_data_ex[13]    <= #U_DLY rc_tuser_discontinue;
            rc_cplr_data_ex[12:10] <= #U_DLY 3'b0;
            casex( m_axis_rc_tkeep )
            4'b0001 : rc_cplr_data_ex[9:8] <= #U_DLY 2'd0;
            4'b001? : rc_cplr_data_ex[9:8] <= #U_DLY 2'd1;
            4'b01?? : rc_cplr_data_ex[9:8] <= #U_DLY 2'd2;
            default : rc_cplr_data_ex[9:8] <= #U_DLY 2'd3;
            endcase
            rc_cplr_data_ex[7:4]   <= #U_DLY 4'b0;
            rc_cplr_data_ex[3:0]   <= #U_DLY 4'b0;
        end
        else
            ;
    end
endgenerate

always @ ( posedge pcie_clk )
    rc_cplr_wen <= #U_DLY m_axis_rc_tvalid & m_axis_rc_tready;

    //data接收顺序调整
always @ ( posedge pcie_clk )
    rc_cplr_data <= #U_DLY m_axis_rc_tdata;




endmodule




