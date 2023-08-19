
`timescale 100ps / 1ps

module pcie_cq_intf #(
parameter   DWIDTH  = 256
)(
input                       pcie_clk            ,
input                       pcie_rst            ,
input                       pcie_link_up        ,
    // pciecore interface GEN3 for xilinex kintex ultrascale+
input                       m_axis_cq_tlast     ,
input       [DWIDTH-1:0]    m_axis_cq_tdata     ,
input       [87: 0]         m_axis_cq_tuser     ,
input       [DWIDTH/32-1:0] m_axis_cq_tkeep     ,
output  reg                 m_axis_cq_tready    ,
input                       m_axis_cq_tvalid    ,
    //pcie_user_tx interface
output  reg [15: 0]         cq_oper_data_ex     ,   //Pcie write/read operation
output  reg [159:0]         cq_oper_data        ,
output  reg                 cq_oper_wen         ,
input                       cq_oper_ready       ,

//output  reg                 read_req            ,
//output  reg [ 7: 0]         req_tag             ,
//output  reg [255:0]         cap_cq_data         ,
//output  reg [ 1: 0]         cap_cq_wen          ,
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
localparam  KEEP_M      = 12 ;
localparam  KEEP_L      = 8  ;
localparam  FBE_M       = 7  ;
localparam  FBE_L       = 4  ;
localparam  LBE_M       = 3  ;
localparam  LBE_L       = 0  ;







wire    [ 3: 0]         cq_tuser_first_be   ;
wire    [ 3: 0]         cq_tuser_last_be    ;
wire                    cq_tuser_is_sop     ;
wire                    cq_tuser_discontinue;

//reg     [ 7: 0]         target_func         ;
//reg     [63: 0]         address             ;
reg     [15: 0]         tmp_data_ex         ;
reg     [159:0]         tmp_data            ;
reg                     tmp_wen             ;

//opt timing
reg                     cq_oper_ready_1d    ;
always@(posedge pcie_clk)
    cq_oper_ready_1d <= cq_oper_ready;


assign odbg_info = {14'b0,cq_oper_ready_1d,m_axis_cq_tready};

assign  cq_tuser_first_be       = m_axis_cq_tuser[3:0];
assign  cq_tuser_last_be        = m_axis_cq_tuser[7:4];
assign  cq_tuser_is_sop         = m_axis_cq_tuser[40];
assign  cq_tuser_discontinue    = m_axis_cq_tuser[41];



    //m_axis_cq_tvalid有效过程中，即使将满，也不反压ipcore
always @ ( posedge pcie_clk )
begin
    if ( ~cq_oper_ready_1d & (( ~m_axis_cq_tvalid ) | ( m_axis_cq_tvalid & m_axis_cq_tlast )))
        m_axis_cq_tready <= #U_DLY 1'b0;
    else if ( cq_oper_ready_1d )
        m_axis_cq_tready <= #U_DLY 1'b1;
    else
        ;
end
    //m_axis_cq 接收数据写使能
always @ ( posedge pcie_clk )
    tmp_wen <= #U_DLY m_axis_cq_tvalid & m_axis_cq_tready & m_axis_cq_tlast;

generate if(DWIDTH==256)
begin
    always @ ( posedge pcie_clk )
        tmp_data <= #U_DLY m_axis_cq_tdata[159:0];
    //keep位计算
    always @ ( posedge pcie_clk )
        tmp_data_ex[KEEP_M:KEEP_L] <= #U_DLY m_axis_cq_tkeep[4:0];
end
else if(DWIDTH==128)
begin
    //data接收顺序调整
    always @ ( posedge pcie_clk )
    begin
        if(m_axis_cq_tvalid & m_axis_cq_tready)
        begin
            tmp_data[159:128] <= #U_DLY (~cq_tuser_is_sop & m_axis_cq_tlast)? m_axis_cq_tdata[31:0] : 32'b0;
            tmp_data[127:0]   <= #U_DLY (cq_tuser_is_sop)? m_axis_cq_tdata[127:0] : tmp_data[127:0];
        end
        else
            ;
    end
    //keep位计算
    always @ ( posedge pcie_clk )
        tmp_data_ex[KEEP_M:KEEP_L] <= #U_DLY (cq_tuser_is_sop & m_axis_cq_tlast)? {1'b0,m_axis_cq_tkeep[3:0]} :
                                             (m_axis_cq_tlast)?                   5'h1f :
                                                                                  5'b0;
end
endgenerate




    //err位计算，暂时不处理接口上的parity err，只做告警处理
always @ ( posedge pcie_clk )
    tmp_data_ex[ERR] <= #U_DLY cq_tuser_discontinue;

    //sop位计算
always @ ( posedge pcie_clk )
    tmp_data_ex[SOP] <= #U_DLY 1'b1;

    //eop位计算
always @ ( posedge pcie_clk )
    tmp_data_ex[EOP] <= #U_DLY m_axis_cq_tlast;


    //firstBE/lastBE位计算
always @ ( posedge pcie_clk )
begin
    if(m_axis_cq_tvalid & m_axis_cq_tready & cq_tuser_is_sop)
    begin
        tmp_data_ex[FBE_M:FBE_L] <= #U_DLY cq_tuser_first_be;
        tmp_data_ex[LBE_M:LBE_L] <= #U_DLY cq_tuser_last_be ;
    end
    else
        ;
end



always @ ( posedge pcie_clk )
begin
    cq_oper_data_ex <= #U_DLY tmp_data_ex;
    cq_oper_data    <= #U_DLY tmp_data;
    cq_oper_wen     <= #U_DLY tmp_wen;
end

//always@(posedge pcie_clk)
//begin
//    if(m_axis_cq_tvalid & m_axis_cq_tready & cq_tuser_is_sop & m_axis_cq_tlast & m_axis_cq_tkeep==8'h0f & m_axis_cq_tdata[78:75]==4'b0000)
//    begin
//        req_tag  <= m_axis_cq_tdata[103:96];
//        read_req <= 1'b1;
//    end
//    else
//        read_req <= 1'b0;
//end
//
//always@(posedge pcie_clk)
//begin
//    if(m_axis_cq_tvalid & m_axis_cq_tready)
//    begin
//        cap_cq_data <= #U_DLY m_axis_cq_tdata;
//        if(cq_tuser_is_sop & m_axis_cq_tlast & m_axis_cq_tkeep==8'h0f & m_axis_cq_tdata[78:75]==4'b0000)    //read
//            cap_cq_wen <= #U_DLY 2'b01;
//        else if(cq_tuser_is_sop & m_axis_cq_tlast & m_axis_cq_tkeep==8'hff & m_axis_cq_tdata[78:75]==4'b0001)   //write                                                                                             //write
//            cap_cq_wen <= #U_DLY 2'b10;
//        else
//            cap_cq_wen <= #U_DLY 2'b0;
//    end
//    else
//        cap_cq_wen <= #U_DLY 2'b0;
//end


endmodule




