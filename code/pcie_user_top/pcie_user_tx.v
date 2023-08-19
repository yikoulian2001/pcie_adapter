
`timescale 100ps / 1ps
module pcie_user_tx #(
parameter   MAXPAYLOAD  = 256,
parameter   MAXREADREQ  = 512,
parameter   DWIDTH      = 256
)(
// ===========================================================================
//part0: port singal define
// ===========================================================================
input                   user_clk            ,
input                   user_rst            ,

input                   iPcie_OPEN          ,
output      [31: 0]     odbg_info           ,

//Pcie_rq_intf interface
output  reg [15: 0]     rq_oper_data_ex     ,
output  reg [DWIDTH-1:0]rq_oper_data        ,   //Pcie write operation
output  reg             rq_oper_wen         ,
input                   rq_oper_ready       ,
//Tag manage interface
input                   res_tag_empty       ,
output                  res_tag_ren         ,
input       [ 7: 0]     res_tag_dout        ,
output      [143:0]     curr_tag_msg        ,

input       [ 7: 0]     retry_tag           ,
input       [143:0]     retry_data          ,
input                   retry_req           ,
output                  retry_ack           ,
//Tx Buffer interface
output                  oPcie_tx_ready      ,       //按256byte为分片形式送出
input       [143:0]     iPcie_tx_headin     ,
input                   iPcie_tx_Hwrreq     ,
input       [DWIDTH-1:0]iPcie_tx_datain     ,
input                   iPcie_tx_wrreq

);



// only for simulation delay
localparam  U_DLY          = 1 ;
localparam  MAXPAYLOAD_BIT = clogb2(MAXPAYLOAD);
localparam  MAXREADREQ_BIT = clogb2(MAXREADREQ);
localparam  BEATWIDTH_BIT  = clogb2(DWIDTH/8); //单拍字节数所占bit
localparam  DATANUM_BIT    = MAXPAYLOAD_BIT - BEATWIDTH_BIT;    //one cycle is 32byte data width

function integer clogb2;
input [31:0] depthbit;
integer i;
begin
    clogb2 = 1;
    for (i = 0; 2**i < depthbit; i = i + 1)
    begin
        clogb2 = i + 1;
    end
end
endfunction
/***********************************************************************************************************************
when sop, data is information, define as
| 143 | 142 | 141 | 140 | 139:96   | 95:93   | 92:80    | 79:64   | 63:0     |
| sop | eop | err | rsv | userinfo | 000:mwr | 5'b0,rid | req_len | dma_addr |
| sop | eop | err | rsv | userinfo | 010:mrd | 5'b0,rid | req_len | dma_addr |

***********************************************************************************************************************/

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
    //用户侧请求类型,格式定义
localparam  REQ_TYPE_MWR    = 3'B000    ;
localparam  REQ_TYPE_MRD    = 3'B010    ;
localparam  REQ_TYPE_INT    = 3'B110    ;
localparam  REQ_TYPE_ATS    = 3'B001    ;

    //descriptor请求类型定义
localparam  TLP_MRD         = 4'B0000   ;
localparam  TLP_MWR         = 4'B0001   ;
localparam  TLP_ATS         = 4'B1110   ;


wire    [143:0]                 jPcie_seg_headin    ;
wire                            jPcie_seg_Hwrreq    ;
wire    [DWIDTH-1:0]            jPcie_seg_datain    ;
wire                            jPcie_seg_wrreq     ;

wire                            jPcie_seg_empty     ;
wire                            jPcie_seg_ready     ;

wire    [143:0]                 jPcie_seg_headout   ;
wire                            jPcie_seg_Hrdreq    ;
//reg                             jPcie_seg_Hrdreq_1d ;
wire                            jPcie_seg_wr_drop   ;

wire    [DWIDTH-1:0]            jPcie_seg_dataout   ;
reg     [DWIDTH-1:0]            jPcie_seg_dataout_1d;
wire                            jPcie_seg_rdreq     ;
reg                             jPcie_seg_rdreq_1d  ;
reg                             jPcie_seg_rdreq_2d  ;

wire                            load_head           ;
//fsm control signal
reg     [ 3: 0]                 jtx_state           ;
wire                            curr_idle           ;
wire                            curr_mwr            ;
reg                             curr_mwr_1d         ;
reg                             curr_mwr_2d         ;
wire                            curr_mrd            ;
reg                             curr_mrd_1d         ;
reg                             curr_mrd_2d         ;
reg                             curr_mrd_3d         ;
wire                            curr_rty            ;
reg                             curr_rty_1d         ;
reg                             curr_rty_2d         ;
reg                             curr_rty_3d         ;
reg     [DATANUM_BIT:0]         jtx_statecnt        ;

reg     [DWIDTH-1:0]            jPcie_tx_data       ;



//延迟信号，同步读数据，产生最后数据尾标志

wire                            retry_sel           ;
//wire    [ 7: 0]                 req_seq_id          ;
//reg     [ 7: 0]                 req_seq_id_1d       ;
//reg     [ 7: 0]                 req_seq_id_2d       ;
//reg     [ 7: 0]                 req_seq_id_3d       ;
wire                            req_type            ;
wire                            req_head_sop        ;
reg                             req_head_sop_1d     ;
reg                             req_head_sop_2d     ;
//reg                             req_head_sop_3d     ;
wire                            req_head_eop        ;
reg                             req_head_eop_1d     ;
reg                             req_head_eop_2d     ;
//reg                             req_head_eop_3d     ;
wire    [63: 0]                 req_start_addr      ;
reg     [63: 0]                 req_start_addr_1d   ;
wire    [ 7: 0]                 req_rid             ;
reg     [ 7: 0]                 req_rid_1d          ;
wire    [15: 0]                 req_curr_len        ;
wire    [15: 0]                 req_addr_end        ;
wire    [15: 0]                 req_addr_end_tmp    ;
wire                            req_one_dw_len      ;
reg     [ 9: 0]                 req_dw_len          ;
wire    [ 1: 0]                 req_last_be_tmp     ;

reg     [DATANUM_BIT:0]         req_rd_num          ;
//reg                             add_flg             ;

reg     [ 3: 0]                 req_first_be_mask   ;
reg     [ 3: 0]                 req_first_be_pre    ;
reg     [ 3: 0]                 req_first_be        ;
reg     [ 3: 0]                 req_first_be_1d     ;
reg     [ 3: 0]                 req_first_be_2d     ;
reg     [ 3: 0]                 req_last_be         ;
reg     [ 3: 0]                 req_last_be_1d      ;
reg     [ 3: 0]                 req_last_be_2d      ;

wire                            req_rd_first        ;
reg                             req_rd_first_1d     ;
reg                             req_rd_first_2d     ;
wire                            req_rd_last         ;
reg                             req_rd_last_1d      ;
reg                             req_rd_last_2d      ;

reg     [ 3: 0]                 req_mwr_tkeep       ;
reg     [ 3: 0]                 req_mwr_tkeep_1d    ;
reg     [ 3: 0]                 req_mwr_tkeep_2d    ;

reg                             pcie_wr_en          ;
reg                             pcie_wr_first       ;
//reg                             pcie_wr_first_1d    ;
reg                             pcie_wr_last        ;
reg                             req_is_end          ;

//mwr descriptor
wire                            req_mwr_des_force_ecrc ;
wire    [ 2: 0]                 req_mwr_des_attr       ;
wire    [ 2: 0]                 req_mwr_des_tc         ;
wire                            req_mwr_des_rid_en     ;
wire    [15: 0]                 req_mwr_des_cpl_id     ;
wire    [ 7: 0]                 req_mwr_des_tag        ;
wire    [15: 0]                 req_mwr_des_rid        ;
wire                            req_mwr_des_poison     ;
wire    [ 3: 0]                 req_mwr_des_req_type   ;
wire    [10: 0]                 req_mwr_des_dw_cnt     ;
wire    [61: 0]                 req_mwr_des_addr       ;
wire    [ 1: 0]                 req_mwr_des_at         ;
reg     [127:0]                 req_mwr_des_header     ;
reg     [127:0]                 req_mwr_des_header_1d  ;
reg     [127:0]                 req_mwr_des_header_2d  ;

reg     [ 7: 0]                 jdrop_cnt           ;


localparam  S_IDLE  = 4'b0001   ;   //空闲状态
localparam  S_MWR   = 4'b0010   ;   //写分片数据状态
localparam  S_MRD   = 4'b0100   ;   //读分片数据状态
localparam  S_RTY   = 4'b1000   ;

assign odbg_info[31:16] = {jdrop_cnt,
                           2'b0,jPcie_seg_empty,rq_oper_ready,
                           jtx_state[3:0]};
always @ ( posedge user_clk )
begin
    if ( user_rst )
        jdrop_cnt <= #U_DLY 8'b0;
    else if( jPcie_seg_wr_drop )
        jdrop_cnt <= #U_DLY jdrop_cnt + 1'b1;
    else
        ;
end

//=============================================================================================
//PCIE x8 Gen3 port
//=============================================================================================

pcie_user_seg #(
    .MAXPAYLOAD         ( MAXPAYLOAD ),
    .MAXREADREQ         ( MAXREADREQ ),
    .DWIDTH             ( DWIDTH     )
) u_pcie_user_seg(
    .user_clk           ( user_clk          ),
    .user_rst           ( user_rst          ),

    .iPcie_OPEN         ( iPcie_OPEN        ),
    .odbg_info          ( odbg_info[15:0]   ),

    .iPcie_seg_ready    ( jPcie_seg_ready   ),
    .oPcie_seg_headin   ( jPcie_seg_headin  ),
    .oPcie_seg_Hwrreq   ( jPcie_seg_Hwrreq  ),
    .oPcie_seg_datain   ( jPcie_seg_datain  ),
    .oPcie_seg_wrreq    ( jPcie_seg_wrreq   ),

    .oPcie_tx_ready     ( oPcie_tx_ready    ),       //按256byte为分片形式送出
    .iPcie_tx_headin    ( iPcie_tx_headin   ),
    .iPcie_tx_Hwrreq    ( iPcie_tx_Hwrreq   ),
    .iPcie_tx_datain    ( iPcie_tx_datain   ),
    .iPcie_tx_wrreq     ( iPcie_tx_wrreq    )
);

//===================================================
//  按分片缓存数据
//===================================================
//每个head附带的数据为512byte
//优化时序，打一拍处理
pcie_wr_fifo #(
    .BUFUNIT        ( MAXPAYLOAD ),     //2048 or 256
    .DWIDTH         ( DWIDTH     )      //256 or 128 or 64
) u_pcie_wr_fifo(
    .user_clk       ( user_clk          ),
    .user_rst       ( user_rst          ),

    .oPcie_ready    ( jPcie_seg_ready   ),       //按256byte为分片形式送出
    .iPcie_headin   ( jPcie_seg_headin  ),
    .iPcie_Hwrreq   ( jPcie_seg_Hwrreq  ),
    .iPcie_datain   ( jPcie_seg_datain  ),
    .iPcie_wrreq    ( jPcie_seg_wrreq   ),

    .oPcie_empty    ( jPcie_seg_empty   ),       //按256byte为分片形式送出
    .oPcie_headout  ( jPcie_seg_headout ),
    .iPcie_Hrdreq   ( jPcie_seg_Hrdreq  ),
    .oPcie_dataout  ( jPcie_seg_dataout ),
    .iPcie_rdreq    ( jPcie_seg_rdreq   )
);

//================================================================================//
assign jPcie_seg_wr_drop   = curr_idle & ~iPcie_OPEN & ~jPcie_seg_empty ;

assign retry_sel = retry_req & (curr_idle | curr_rty);

//操作类型
assign load_head = curr_idle & ~jPcie_seg_empty;
assign req_type       = (retry_sel)? 1'b1 :
                        (jPcie_seg_headout[95:93]==REQ_TYPE_MWR)? 1'b0 : 1'b1;
//assign req_seq_id     = jPcie_seg_headout[151:144];
assign req_head_sop   = (retry_sel)? retry_data[143] : jPcie_seg_headout[143];
assign req_head_eop   = (retry_sel)? retry_data[142] : jPcie_seg_headout[142];
//操作起始地址
assign req_start_addr = (retry_sel)? retry_data[63:0] : jPcie_seg_headout[63:0];   //address
//长度
assign req_curr_len   = (retry_sel)? retry_data[79:64] : jPcie_seg_headout[79:64];
assign req_rid        = (retry_sel)? retry_data[87:80] : jPcie_seg_headout[87:80];


//将长度和位宽对应的地址相加，用于产生读上级缓存的拍数
assign req_addr_end   = (~req_type)?            req_curr_len + {14'b0,req_start_addr[1:0]}+16'd16 :   //包含增加的pcie 4dw帧头后的长度
                        (req_curr_len==16'b0)?  16'b0 :
                                                req_curr_len + {{(16-BEATWIDTH_BIT){1'b0}},req_start_addr[BEATWIDTH_BIT-1:0]};
//将长度和dword位宽地址相加，用于产生实际操作的dword个数
assign req_addr_end_tmp = (req_curr_len==16'b0)? 16'b0 : (req_curr_len + {14'b0,req_start_addr[1:0]});

//本次操作的dword信息
always @ ( posedge user_clk )
begin
    if (~req_type)
    begin
        if ( req_addr_end_tmp[1:0]==2'b0)
            req_dw_len <= #U_DLY req_addr_end_tmp[11:2] ;
        else
            req_dw_len <= #U_DLY req_addr_end_tmp[11:2] + 1'b1;
    end
    else
    begin
        if ( req_addr_end[1:0]==2'b0)
            req_dw_len <= #U_DLY req_addr_end[11:2] ;
        else
            req_dw_len <= #U_DLY req_addr_end[11:2] + 1'b1;
    end
end



//当前写操作情况下，读取上级缓存数据的拍数
always @ ( posedge user_clk )
begin
    if ( load_head )
    begin
        if(req_addr_end[BEATWIDTH_BIT-1:0]=={BEATWIDTH_BIT{1'b0}})
            req_rd_num <= #U_DLY req_addr_end[MAXPAYLOAD_BIT:BEATWIDTH_BIT] - 1'b1 ;
        else
            req_rd_num <= #U_DLY req_addr_end[MAXPAYLOAD_BIT:BEATWIDTH_BIT] ;
    end
    else
        ;
end



//always@(posedge user_clk)
//begin
//    req_seq_id_1d <= #U_DLY req_seq_id;
//    req_seq_id_2d <= #U_DLY req_seq_id_1d;
//    req_seq_id_3d <= #U_DLY req_seq_id_2d;
//end
always@(posedge user_clk)
begin
    req_head_sop_1d <= #U_DLY req_head_sop;
    req_head_sop_2d <= #U_DLY req_head_sop_1d;
//    req_head_sop_3d <= #U_DLY req_head_sop_2d;
end
always@(posedge user_clk)
begin
    req_head_eop_1d <= #U_DLY req_head_eop;
    req_head_eop_2d <= #U_DLY req_head_eop_1d;
//    req_head_eop_3d <= #U_DLY req_head_eop_2d;
end




//delay
always @ ( posedge user_clk )
    req_start_addr_1d <= #U_DLY req_start_addr;

always @ ( posedge user_clk )
    req_rid_1d <= #U_DLY req_rid;

//===========================================================================
//  TX data transmit
//===========================================================================


assign curr_idle = jtx_state[0] ;
assign curr_mwr  = jtx_state[1] ;
assign curr_mrd  = jtx_state[2] ;
assign curr_rty  = jtx_state[3] ;


//FSM
always @ ( posedge user_clk )
begin
    if ( user_rst )
        jtx_state <= #U_DLY S_IDLE ;
    else
    begin
        case ( jtx_state )
        S_IDLE  :   if (iPcie_OPEN & retry_req & rq_oper_ready )
                        jtx_state <= #U_DLY S_RTY ;
                    else if (iPcie_OPEN & ~jPcie_seg_empty & rq_oper_ready ) //当前操作为写操作
                    begin
                        if(~req_type)
                            jtx_state <= #U_DLY S_MWR ;
                        else if(~res_tag_empty)
                            jtx_state <= #U_DLY S_MRD ;
                        else
                            jtx_state <= #U_DLY S_IDLE;
                    end
                    else
                        jtx_state <= #U_DLY S_IDLE ;
        S_MWR   :   if ( jPcie_seg_Hrdreq )         //在分片结束时判断eop标志
                        jtx_state <= #U_DLY S_IDLE ;
                    else
                        jtx_state <= #U_DLY S_MWR ;
        S_MRD   :   jtx_state <= #U_DLY S_IDLE ;
        S_RTY   :   jtx_state <= #U_DLY S_IDLE ;
        default :   jtx_state <= #U_DLY S_IDLE ;
        endcase
    end
end

assign retry_ack = curr_rty;
assign res_tag_ren  = curr_mrd ;
assign curr_tag_msg = jPcie_seg_headout;

//assign jPcie_seg_drop = curr_idle & ~jPcie_OPEN_chain[15] & ~jPcie_seg_empty ;
generate if(DWIDTH==256)
    assign jPcie_seg_rdreq = curr_mwr;
else if(DWIDTH==128)
    assign jPcie_seg_rdreq = curr_mwr & ( jtx_statecnt > {(DATANUM_BIT+1){1'b0}} );
//else if(DWIDTH==64)
//    assign jPcie_seg_rdreq = curr_mwr & ( jtx_statecnt > {{(DATANUM_BIT){1'b0}},1'b1} );
endgenerate

assign jPcie_seg_Hrdreq = req_rd_last | curr_mrd ;


always @ ( posedge user_clk )
begin
    curr_mwr_1d <= #U_DLY curr_mwr;
    curr_mwr_2d <= #U_DLY curr_mwr_1d;
end
always @ ( posedge user_clk )
begin
    curr_mrd_1d <= #U_DLY curr_mrd;
    curr_mrd_2d <= #U_DLY curr_mrd_1d;
    curr_mrd_3d <= #U_DLY curr_mrd_2d;
    curr_rty_1d <= #U_DLY curr_rty;
    curr_rty_2d <= #U_DLY curr_rty_1d;
    curr_rty_3d <= #U_DLY curr_rty_2d;
end

//产生实际写操作的sop和eop
assign req_rd_first = curr_mwr & ( jtx_statecnt == {(DATANUM_BIT+1){1'b0}} );
assign req_rd_last  = curr_mwr & ( jtx_statecnt == req_rd_num ); //(jPcie_seg_Hrdreq & ~add_flg) | (jPcie_seg_Hrdreq_1d & add_flg);

//状态机内部进行写操作的计数寄存器
always @ ( posedge user_clk )
begin
    if( curr_mwr )
        jtx_statecnt <= #U_DLY jtx_statecnt + 1'b1 ;
    else
        jtx_statecnt <= #U_DLY {(DATANUM_BIT+1){1'b0}} ;
end




//延迟打拍
always @ ( posedge user_clk )
begin
    jPcie_seg_rdreq_1d <= #U_DLY jPcie_seg_rdreq;
    jPcie_seg_rdreq_2d <= #U_DLY jPcie_seg_rdreq_1d;
end
//always @ ( posedge user_clk )
//    jPcie_seg_Hrdreq_1d <= #U_DLY jPcie_seg_Hrdreq;

always @ ( posedge user_clk )
begin
    req_rd_first_1d <= #U_DLY req_rd_first;
    req_rd_first_2d <= #U_DLY req_rd_first_1d;
end

always @ ( posedge user_clk )
begin
    req_rd_last_1d <= #U_DLY req_rd_last;
    req_rd_last_2d <= #U_DLY req_rd_last_1d;
end



//===========================================================================
//  数据的偏移及读写控制
//===========================================================================
always @ ( posedge user_clk )
begin
    if ( jPcie_seg_rdreq_2d )
        jPcie_seg_dataout_1d <= #U_DLY jPcie_seg_dataout;
    else
        ;
end

//数据偏移，腾出128bit，用于填充写操作的pcie head
generate if(DWIDTH==256)
begin
    always @ ( posedge user_clk )
        jPcie_tx_data <= #U_DLY { jPcie_seg_dataout[127:0], jPcie_seg_dataout_1d[255:128] };
end
else if(DWIDTH==128)
begin
    always @ ( posedge user_clk )
        jPcie_tx_data <= #U_DLY jPcie_seg_dataout;
end
endgenerate

always @ ( posedge user_clk )
    pcie_wr_en <= #U_DLY curr_mwr_2d;

always @ ( posedge user_clk )
    pcie_wr_first <= #U_DLY req_rd_first_2d;

always @ ( posedge user_clk )
    pcie_wr_last <= #U_DLY req_rd_last_2d;

//always @ ( posedge user_clk )
//    pcie_wr_first_1d <= pcie_wr_first;

//===========================================================================
//  判断是否越界，并计算每次操作的地址及长度，firstBE及lastBE
//===========================================================================
/***********************************************************************************************************************
    当req_dw_len为1个DW时,first_be仅部分有效,last_be全部无效
    当req_dw_len为2个DW及以上时,first_be/last_be必然连续,逻辑不支持不连续的请求(虽然协议允许)
    计算first_be与last_be,注意长度小于等于1个DW的情况;当长度超过1个DW时
***********************************************************************************************************************/
//当只有一个dword时，产生该标志
assign req_one_dw_len = (req_dw_len==10'd1)?  1'b1 : 1'b0;

assign req_last_be_tmp = req_addr_end_tmp[1:0];

always @ ( posedge user_clk )
begin
    case( req_last_be_tmp )
    2'b00   :   req_first_be_mask <= #U_DLY 4'b1111;
    2'b01   :   req_first_be_mask <= #U_DLY 4'b0001;
    2'b10   :   req_first_be_mask <= #U_DLY 4'b0011;
    default :   req_first_be_mask <= #U_DLY 4'b0111;
    endcase
end

always @ ( posedge user_clk )
begin
    case ( req_start_addr[1:0] )
    2'b00   :   req_first_be_pre <= #U_DLY 4'b1111;
    2'b01   :   req_first_be_pre <= #U_DLY 4'b1110;
    2'b10   :   req_first_be_pre <= #U_DLY 4'b1100;
    default :   req_first_be_pre <= #U_DLY 4'b1000;
    endcase
end

    //计算first_be
always @ ( posedge user_clk )
begin
    if ( req_dw_len == 10'b0)
        req_first_be <= #U_DLY 4'b0;
    else if ( req_one_dw_len )
        req_first_be <= #U_DLY req_first_be_pre & req_first_be_mask;
    else
        req_first_be <= #U_DLY (req_type)? 4'hf : req_first_be_pre;
end
    //计算last_be
always @ ( posedge user_clk )
begin
    if ( req_dw_len == 10'b0)
        req_last_be <= #U_DLY 4'b0;
    else if ( req_one_dw_len )
        req_last_be <= #U_DLY 4'b0;
    else
        req_last_be <= #U_DLY (req_type)? 4'hf : req_first_be_mask;
end

always @ ( posedge user_clk )
begin
    req_first_be_1d <= #U_DLY req_first_be;
    req_first_be_2d <= #U_DLY req_first_be_1d;
end
always @ ( posedge user_clk )
begin
    req_last_be_1d <= #U_DLY req_last_be;
    req_last_be_2d <= #U_DLY req_last_be_1d;
end

//=======================================================
//  写操作
//=======================================================

    //生成descriptor头部
assign  req_mwr_des_force_ecrc  = 1'b0;
assign  req_mwr_des_attr        = 3'b0;
assign  req_mwr_des_tc          = 3'b0;
assign  req_mwr_des_rid_en      = 1'b0;
assign  req_mwr_des_cpl_id      = 16'h0;    //mwr不需要此字段
assign  req_mwr_des_tag         = (retry_sel)? retry_tag :
                                  (req_type)? res_tag_dout : 8'b0;
assign  req_mwr_des_rid         = {8'b0,req_rid}; //req_rid_mwr;
assign  req_mwr_des_poison      = 1'b0;
assign  req_mwr_des_req_type    = (req_type)? TLP_MRD : TLP_MWR;
assign  req_mwr_des_dw_cnt      = (req_dw_len==10'b0)? 11'd1 : {1'b0,req_dw_len};
assign  req_mwr_des_addr        = (req_type)? {req_start_addr[63:BEATWIDTH_BIT],{(BEATWIDTH_BIT-2){1'b0}}} : req_start_addr[63:2];
assign  req_mwr_des_at          = 2'b00;


    //根据ipcore接口,构造AXI接口格式
always @ ( posedge user_clk )
begin
    if ( req_rd_first | curr_mrd | curr_rty)
        req_mwr_des_header <= #U_DLY { req_mwr_des_force_ecrc,req_mwr_des_attr,req_mwr_des_tc,req_mwr_des_rid_en,
                                       req_mwr_des_cpl_id,req_mwr_des_tag,req_mwr_des_rid,req_mwr_des_poison,
                                       req_mwr_des_req_type,req_mwr_des_dw_cnt,req_mwr_des_addr,req_mwr_des_at};
    else
        ;
end

always @ ( posedge user_clk )
begin
    req_mwr_des_header_1d <= #U_DLY req_mwr_des_header;
    req_mwr_des_header_2d <= #U_DLY req_mwr_des_header_1d;
end


generate if(DWIDTH==256)
begin
    always @ ( posedge user_clk )
    begin
        if ( req_rd_last )
        begin
            req_mwr_tkeep[3]   <= #U_DLY 1'b0;
            req_mwr_tkeep[2:0] <= #U_DLY req_dw_len[2:0] + 3'd3;
        end
        else
            req_mwr_tkeep <= #U_DLY 4'b0 ;
    end
end
else if(DWIDTH==128)
begin
    always @ ( posedge user_clk )
    begin
        if ( req_rd_last )
        begin
            req_mwr_tkeep[3:2] <= #U_DLY 2'b0;
            req_mwr_tkeep[1:0] <= #U_DLY req_dw_len[1:0] + 2'd3;
        end
        else
            req_mwr_tkeep <= #U_DLY 4'b0 ;
    end
end
endgenerate

always @ ( posedge user_clk )
begin
    req_mwr_tkeep_1d <= #U_DLY req_mwr_tkeep;
    req_mwr_tkeep_2d <= #U_DLY req_mwr_tkeep_1d;
end
always@(posedge user_clk)
begin
    if(curr_mwr_2d & req_rd_last_2d & req_head_eop_2d)
        req_is_end <= #U_DLY 1'b1;
    else if(curr_mrd_2d & req_head_eop_2d)
        req_is_end <= #U_DLY 1'b1;
    else if(curr_rty_2d & req_head_eop_2d)
        req_is_end <= #U_DLY 1'b1;
    else
        req_is_end <= #U_DLY 1'b0;
end


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

always @ ( posedge user_clk )
begin
    if ( pcie_wr_en & pcie_wr_first )      //写操作，写pcie帧头
    begin
//        rq_oper_data_ex[23:16] <= #U_DLY req_seq_id_3d;
        rq_oper_data_ex[15]    <= #U_DLY pcie_wr_first;
        rq_oper_data_ex[14]    <= #U_DLY pcie_wr_last;
        rq_oper_data_ex[13]    <= #U_DLY 1'b0;
        rq_oper_data_ex[12]    <= #U_DLY req_is_end;
        rq_oper_data_ex[11:8]  <= #U_DLY req_mwr_tkeep_2d;
        rq_oper_data_ex[7:4]   <= #U_DLY req_first_be_2d;
        rq_oper_data_ex[3:0]   <= #U_DLY req_last_be_2d;
    end
    else if( pcie_wr_en | pcie_wr_last)        //写操作，写数据
    begin
//        rq_oper_data_ex[23:16] <= #U_DLY req_seq_id_3d;
        rq_oper_data_ex[15]    <= #U_DLY 1'b0;
        rq_oper_data_ex[14]    <= #U_DLY pcie_wr_last;
        rq_oper_data_ex[13]    <= #U_DLY 1'b0;
        rq_oper_data_ex[12]    <= #U_DLY req_is_end;
        rq_oper_data_ex[11:8]  <= #U_DLY req_mwr_tkeep_2d;
        rq_oper_data_ex[7:4]   <= #U_DLY 4'b0;
        rq_oper_data_ex[3:0]   <= #U_DLY 4'b0;
    end
    else if(curr_mrd_3d | curr_rty_3d)
    begin
        rq_oper_data_ex[15:14] <= #U_DLY 2'b11;
        rq_oper_data_ex[13:12] <= #U_DLY {1'b0,req_is_end};
        rq_oper_data_ex[11:8]  <= #U_DLY 4'h3;
        rq_oper_data_ex[7:4]   <= #U_DLY req_first_be_2d;
        rq_oper_data_ex[3:0]   <= #U_DLY req_last_be_2d;
    end
    else
        ;
end

generate if(DWIDTH==256)
begin
    always @ ( posedge user_clk )
    begin
        if ( pcie_wr_en & pcie_wr_first )      //写操作，写pcie帧头
            rq_oper_data <= #U_DLY { jPcie_tx_data[255:128], req_mwr_des_header_2d };
        else if( pcie_wr_en | pcie_wr_last)        //写操作，写数据
            rq_oper_data <= #U_DLY jPcie_tx_data ;
        else if ( curr_mrd_3d | curr_rty_3d )      //读操作，写pcie帧头
            rq_oper_data <= #U_DLY { 128'b0, req_mwr_des_header_2d };
        else
            ;
    end
end
else if(DWIDTH==128)
begin
    always @ ( posedge user_clk )
    begin
        if ( pcie_wr_en & pcie_wr_first )      //写操作，写pcie帧头
            rq_oper_data <= #U_DLY req_mwr_des_header_2d ;
        else if( pcie_wr_en )        //写操作，写数据
            rq_oper_data <= #U_DLY jPcie_tx_data ;
        else if ( curr_mrd_3d | curr_rty_3d )      //读操作，写pcie帧头
            rq_oper_data <= #U_DLY req_mwr_des_header_2d ;
        else
            ;
    end
end
endgenerate

always @ ( posedge user_clk )
begin
    if ( pcie_wr_en | pcie_wr_last)      //写操作
        rq_oper_wen <= #U_DLY 1'b1 ;
    else if ( curr_mrd_3d | curr_rty_3d )      //读操作，写pcie帧头;
        rq_oper_wen <= #U_DLY 1'b1 ;
    else
        rq_oper_wen <= #U_DLY 1'b0 ;
end


endmodule
