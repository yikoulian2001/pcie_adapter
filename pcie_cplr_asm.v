
`timescale 100ps / 1ps
module pcie_cplr_asm #(
parameter   MAXTAG      = 64,
parameter   MAXREADREQ  = 512,
parameter   DWIDTH      = 256
)(
// ===========================================================================
//part0: port singal define
// ===========================================================================
input                       user_clk                ,
input                       user_rst                ,

output      [15: 0]         odbg_info               ,

input                       pcie_clk                ,
input                       pcie_rst                ,
input       [15: 0]         rc_cplr_data_ex         ,
input       [DWIDTH-1:0]    rc_cplr_data            ,   //Pcie read completion
input                       rc_cplr_wen             ,
output  reg                 rc_cplr_ready           ,

//input       [MAXTAG-1:0]    res_tag_timeout_flg     ,
//input       [MAXTAG-1:0]    res_tag_valid_flg       ,
output  reg [MAXTAG-1:0]    cpl_tag_end_flg         ,
output  reg                 tag_tout_pulse          ,
output  reg                 cpl_dw_err              ,
//output  reg [ 5: 0]         err_code                ,
//output  reg [ 7: 0]         res_tag_rclm_din        ,
output                      res_tag_rclm_wen        ,

output      [ 5: 0]         used_tag_radrs          ,
input       [143:0]         used_tag_dout           ,
input                       tag_tout_flg            ,
input                       res_tag_init_done       ,

output      [ 7: 0]         retry_tag               ,
output      [143:0]         retry_data              ,
output                      retry_req               ,
input                       retry_ack               ,
output      [ 7: 0]         cpl_tag                 ,
input                       tag_legal_flg           ,

input                       iPcie_rx_ready          ,
output  reg [143:0]         oPcie_rx_headin         ,
output  reg                 oPcie_rx_Hwrreq         ,
output  reg [DWIDTH-1:0]    oPcie_rx_datain         ,
output  reg                 oPcie_rx_wrreq
);



// only for simulation delay
localparam  U_DLY          = 1 ;
localparam  MAXTAG_BIT     = clogb2(MAXTAG);
localparam  MAXREADREQ_BIT = clogb2(MAXREADREQ);
localparam  BEATWIDTH_BIT  = clogb2(DWIDTH/8); //单拍字节数所占bit
localparam  DATANUM_BIT    = MAXREADREQ_BIT - BEATWIDTH_BIT;  //one cycle is 32byte data width

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
//localparam  MAXTAG       = 7'd32     ;
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
localparam  SOP         = 15 ;
localparam  EOP         = 14 ;
localparam  ERR         = 13 ;
localparam  KEEP_M      = 11 ;
localparam  KEEP_L      = 8  ;
localparam  FBE_M       = 7  ;
localparam  FBE_L       = 4  ;
localparam  LBE_M       = 3  ;
localparam  LBE_L       = 0  ;
    //用户侧请求类型,格式定义
//localparam  REQ_TYPE_MWR    = 3'B000    ;
//localparam  REQ_TYPE_MRD    = 3'B010    ;
//localparam  REQ_TYPE_INT    = 3'B110    ;
//localparam  REQ_TYPE_ATS    = 3'B001    ;

    //descriptor请求类型定义
//localparam  TLP_MRD         = 4'B0000   ;
//localparam  TLP_MWR         = 4'B0001   ;
//localparam  TLP_ATS         = 4'B1110   ;

wire                                    load_head           ;
reg                                     load_head_1d        ;

reg     [95: 0]                         cpl_head            ;
//wire    [11: 0]                         cpl_addr            ;
//wire    [ 7: 0]                         cpl_tag             ;
reg     [ 7: 0]                         cpl_tag_1d          ;
reg     [ 7: 0]                         cpl_tag_2d          ;
wire    [ 2: 0]                         cpl_status          ;
wire    [10: 0]                         cpl_dw_cnt          ;
//wire    [12: 0]                         cpl_byte_cnt        ;
wire    [ 3: 0]                         cpl_err_code        ;
wire                                    cpl_completed       ;
reg                                     cpl_completed_1d    ;

reg                                     sop_flg             ;
//reg                                     sop_flg_1d          ;
//reg                                     sop_flg_2d          ;
//reg                                     sop_flg_3d          ;
//reg                                     sop_flg_rise        ;
wire                                    cut_en              ;
//reg                                     cut_en_1d           ;
//reg                                     cut_en_2d           ;
reg                                     cpl_cover_one       ;
//reg                                     cpl_cover_one_1d    ;

wire    [DWIDTH+15:0]                   rc_cplr_din         ;
wire    [DWIDTH+15:0]                   rc_cplr_dout        ;

wire                                    rc_cplr_ren         ;
reg                                     rc_cplr_ren_1d      ;
wire                                    eop_drop            ;
wire    [15:0]                          rc_cplr_q_ex        ;
reg     [15:0]                          rc_cplr_q_ex_1d     ;
wire    [DWIDTH-1:0]                    rc_cplr_q           ;
reg     [DWIDTH-1:0]                    rc_cplr_q_1d        ;
reg     [DWIDTH-1:0]                    rc_cplr_q_2d        ;
wire                                    rc_cplr_empty       ;
wire                                    rc_cplr_alempty     ;
wire    [ 5: 0]                         rc_cplr_wrusedw     ;
reg                                     rc_cplr_end         ;
reg                                     rc_cplr_end_1d      ;
reg                                     rc_cplr_err         ;

//reg                                     cpl_buf_wen_p2      ;
reg                                     cpl_buf_wen_p1      ;
reg     [DWIDTH-1:0]                    cpl_buf_din         ;
wire                                    cpl_buf_wen         ;

reg                                     cpl_tag_wen_eop     ;

reg     [ 7: 0]                         used_tag_curr       ;
reg     [ 7: 0]                         used_tag_next       ;

reg     [ 1: 0]                         tag_flg             ;
reg     [143:0]                         used_tag_dout_1d    ;

//reg                                       res_tag_valid_flg_and;

reg     [MAXTAG*DATANUM_BIT-1:0]        tag_wadrs           ;
wire    [DATANUM_BIT+5:0]               cpl_buf_wadrs       ;
//reg     [DATANUM_BIT+MAXTAG_BIT-1:0]    cpl_buf_wadrs       ;
wire    [DATANUM_BIT+5:0]               cpl_buf_radrs       ;
reg     [DATANUM_BIT-1:0]               cpl_buf_radrs_l     ;
wire                                    cpl_buf_ren         ;
wire    [DWIDTH-1:0]                    cpl_buf_dout        ;
reg     [DWIDTH-1:0]                    cpl_buf_dout_1d     ;
wire                                    cpl_buf_ren_sop     ;
reg                                     cpl_buf_ren_sop_1d  ;
wire                                    cpl_buf_ren_eop     ;
reg                                     cpl_buf_ren_eop_1d  ;
reg                                     cpl_buf_ren_1d      ;
reg                                     cpl_buf_ren_2d      ;

//reg     [ 1: 0]                         jcpl_state          ;
//wire                                    curr_idle           ;
//wire                                    curr_save           ;
//reg                                     curr_save_1d        ;

reg     [DATANUM_BIT-1:0]               cpl_tag_wadrs       ;
reg                                     cpl_tag_end_tmp     ;
//reg                                     cpl_tag_end_poll    ;
reg     [MAXTAG-1:0]                    cpl_tag_err         ;
reg                                     cpl_tag_err_tmp     ;

reg     [ 3: 0]                         jrsm_state          ;
wire                                    curr_r_idle         ;
wire                                    curr_r_read         ;
wire                                    curr_r_retry        ;
wire                                    curr_r_wait         ;

reg                                     wait_dly            ;
wire    [15: 0]                         len                 ;
wire    [15: 0]                         cpl_len             ;
//reg     [11: 0]                         cpl_len_1d          ;
wire                                    cpl_sop             ;
reg                                     cpl_sop_1d          ;
wire                                    cpl_eop             ;
reg                                     cpl_eop_1d          ;
wire    [BEATWIDTH_BIT-1:0]             offset              ;
wire    [BEATWIDTH_BIT-1:0]             cpl_offset          ;
reg     [BEATWIDTH_BIT-1:0]             cpl_offset_1d       ;
wire    [MAXREADREQ_BIT-1:0]            cpl_addr_end        ;
reg     [DATANUM_BIT-1:0]               cpl_num_s           ;
wire    [DATANUM_BIT-1:0]               cpl_num_m           ;
reg     [DATANUM_BIT-1:0]               cpl_num_sl          ;
wire    [DATANUM_BIT-1:0]               cpl_num             ;
reg     [DATANUM_BIT-1:0]               cpl_cnt             ;
//reg                                     cpl_pkt_err         ;
//reg                                     cpl_pkt_err_1d      ;
reg     [10: 0]                         cpl_real_dw         ;
//reg                                     cpl_dw_err          ;
reg     [ 5: 0]                         err_code            ;

reg     [BEATWIDTH_BIT-1:0]             cpl_sop_offset      ;
reg     [15: 0]                         cpl_whole_len       ;
reg     [15: 0]                         cpl_whole_len_1d    ;
reg     [63: 0]                         cpl_start_adrs      ;
reg     [63: 0]                         cpl_start_adrs_1d   ;
reg     [43: 0]                         cpl_start_info      ;
reg     [43: 0]                         cpl_start_info_1d   ;
reg     [ 7: 0]                         cpl_rid             ;
reg     [ 7: 0]                         cpl_rid_1d          ;

wire    [BEATWIDTH_BIT:0]               cpl_last_len        ;
reg                                     cpl_nocut_en        ;
reg                                     cpl_nocut_en_1d     ;
reg                                     rx_cpl_wen          ;
wire                                    rx_cpl_wen_sop      ;
//reg                                     rx_cpl_wen_sop_1d   ;
wire                                    rx_cpl_wen_eop      ;
reg                                     rx_cpl_wen_eop_1d   ;
reg                                     rx_cpl_wen_eop_2d   ;

wire    [ 7: 0]                         res_tag_rclm_din    ;

//wire                                    tag_legal_flg       ;

//产生读数据指令状态机
//localparam   C_IDLE     = 2'b01 ;
//localparam   C_SAVE     = 2'b10 ;

//处理读返回数据状态机
localparam  R_IDLE  = 4'b0001 ;
localparam  R_READ  = 4'b0010 ;
localparam  R_RETRY = 4'b0100 ;
localparam  R_WAIT  = 4'b1000 ;


assign odbg_info = {2'b0,err_code[5:0],
                    2'b0,rc_cplr_empty,iPcie_rx_ready,
                    jrsm_state[3:0]};

//assign tag_legal_flg = 1'b1;
/********************************************************************
    数据返回
********************************************************************/
//读返回数据缓存，数据内带pcie的head信息

assign rc_cplr_din = {rc_cplr_data_ex,rc_cplr_data};

always@(posedge pcie_clk)
    rc_cplr_ready <= (rc_cplr_wrusedw[5:3]>=3'h3)? 1'b0 : 1'b1 ;
async_fifo #(
    .DATA_WIDTH     ( DWIDTH+16     ),
    .DEPTH_WIDTH    ( 5             ),
    .MEMORY_TYPE    ( "distributed" )
)
u_cplr_fifo(
    .rst            ( pcie_rst          ),
    .wr_clk         ( pcie_clk          ),
    .rd_clk         ( user_clk          ),
    .din            ( rc_cplr_din       ),
    .wr_en          ( rc_cplr_wen       ),
    .rd_en          ( rc_cplr_ren       ),
    .dout           ( rc_cplr_dout      ),
    .full           ( ),
    .empty          ( rc_cplr_empty     ),
    .alempty        ( rc_cplr_alempty   ),
    .wr_data_count  ( rc_cplr_wrusedw   ),
    .wr_rst_busy    ( ),
    .rd_rst_busy    ( )
);
assign rc_cplr_q_ex = rc_cplr_dout[DWIDTH+15:DWIDTH];
assign rc_cplr_q    = rc_cplr_dout[DWIDTH-1:0];



//load completion head descriptor
assign load_head = rc_cplr_ren & rc_cplr_q_ex[SOP];



//从head里获取该Pcie的complete数据信息
assign cpl_tag       = cpl_head[71:64];
assign cpl_status    = cpl_head[45:43];
assign cpl_dw_cnt    = cpl_head[42:32];
//assign cpl_byte_cnt  = cpl_head[28:16];
assign cpl_err_code  = cpl_head[15:12];
//assign cpl_addr      = cpl_head[11:0];
assign cpl_completed = cpl_head[30];

always@(posedge user_clk)
    cpl_completed_1d <= cpl_completed;

assign rc_cplr_ren = ~rc_cplr_empty & (sop_flg != rc_cplr_q_ex[SOP]);
assign eop_drop    = ~rc_cplr_empty & (sop_flg == rc_cplr_q_ex[SOP]);
//always @ ( posedge user_clk )
//begin
//    if ( user_rst )
//        load_head_1d <= 1'b0;
//    else if(rc_cplr_ren)
//        load_head_1d <= load_head;
//    else
//        ;
//end


always @ ( posedge user_clk )
begin

    if ( load_head )
        cpl_head <= #U_DLY rc_cplr_q[95:0];
    else
        ;
end
always @ ( posedge user_clk )
    load_head_1d <= load_head;

//generate real dw cnt in cpld
generate if(DWIDTH==256)
begin
    always @ ( posedge user_clk )
    begin
        if ( user_rst )
            cpl_real_dw <= #U_DLY 11'b0;
        else if( rc_cplr_ren )
        begin
            if(rc_cplr_q_ex[SOP] & rc_cplr_q_ex[EOP])
                cpl_real_dw <= #U_DLY (rc_cplr_q_ex[KEEP_L+:3]<3'd3)? 11'b0 : {8'b0,rc_cplr_q_ex[KEEP_L+:3]} - 11'd2;
            else if(rc_cplr_q_ex[SOP])
                cpl_real_dw <= #U_DLY 11'd5;
            else if(rc_cplr_q_ex[EOP])
                cpl_real_dw <= #U_DLY cpl_real_dw + {8'b0,rc_cplr_q_ex[KEEP_L+:3]} + 1'b1;
            else
                cpl_real_dw <= #U_DLY cpl_real_dw + 11'd8;
        end
        else
            ;
    end
end
else if(DWIDTH==128)
begin
    always @ ( posedge user_clk )
    begin
        if ( user_rst )
            cpl_real_dw <= #U_DLY 11'b0;
        else if( rc_cplr_ren )
        begin
            if(rc_cplr_q_ex[SOP] & rc_cplr_q_ex[EOP])
                cpl_real_dw <= #U_DLY (rc_cplr_q_ex[KEEP_L+:2]<2'd3)? 11'b0 : 11'd1;
            else if(rc_cplr_q_ex[SOP])
                cpl_real_dw <= #U_DLY 11'd1;
            else if(rc_cplr_q_ex[EOP])
                cpl_real_dw <= #U_DLY cpl_real_dw + rc_cplr_q_ex[KEEP_L+:2] + 1'b1;
            else
                cpl_real_dw <= #U_DLY cpl_real_dw + 11'd4;
        end
        else
            ;
    end
end
endgenerate

always@(posedge user_clk)
begin
    if(user_rst)
    begin
        cpl_dw_err <= 1'b0;
        err_code   <= 6'b0;
    end
    else if(rc_cplr_end & (rc_cplr_err | (|cpl_status) | (|cpl_err_code) | (cpl_real_dw!=cpl_dw_cnt)))
    begin
        cpl_dw_err <= 1'b1;
        err_code[1:0] <= (rc_cplr_err)?    2'd0 :
                         (|cpl_status)?    2'd1 :
                         (|cpl_err_code)?  2'd2 :
                                           2'd3;
        err_code[5:2] <= cpl_err_code;
    end
    else
        cpl_dw_err <= 1'b0;
end



always @ ( posedge user_clk )
begin
    if ( user_rst )
        sop_flg <= #U_DLY 1'b0;
    else if((rc_cplr_ren & rc_cplr_q_ex[EOP]) | eop_drop)
        sop_flg <= #U_DLY 1'b0;
    else if( rc_cplr_ren & rc_cplr_q_ex[SOP] )
        sop_flg <= #U_DLY 1'b1;
    else
        ;
end
//always@(posedge user_clk)
//begin
//    sop_flg_1d <= sop_flg;
//    sop_flg_2d <= sop_flg_1d;
//    sop_flg_3d <= sop_flg_2d;
//end


always @ ( posedge user_clk )
begin
    if ( rc_cplr_ren )
        rc_cplr_q_1d <= #U_DLY rc_cplr_q;
    else
        ;
end
always @ (posedge user_clk )
    rc_cplr_q_2d <= #U_DLY rc_cplr_q_1d;

always @ ( posedge user_clk )
begin
    if ( rc_cplr_ren )
        rc_cplr_q_ex_1d <= rc_cplr_q_ex;
    else
        ;
end

always @ ( posedge user_clk )
    rc_cplr_ren_1d <= #U_DLY rc_cplr_ren;

//always @ ( posedge user_clk )
//    curr_save_1d <= curr_save;

always @ ( posedge user_clk )
begin
    cpl_tag_1d <= #U_DLY cpl_tag ;
    cpl_tag_2d <= #U_DLY cpl_tag_1d;
end



//剥掉了completion头以后的数据，写入到对应Tag的缓存里
generate if(DWIDTH==256)
begin
    always @ ( posedge user_clk )
        cpl_buf_din[255:0] <= #U_DLY {rc_cplr_q[95:0], rc_cplr_q_1d[255:96]};
end
else if(DWIDTH==128)
begin
    always @ ( posedge user_clk )
        cpl_buf_din[127:0] <= #U_DLY {rc_cplr_q[95:0], rc_cplr_q_1d[127:96]};
end
endgenerate

always @ ( posedge user_clk )
begin
    if ( user_rst )
        cpl_buf_wen_p1 <= #U_DLY 1'b0;
    else if ( rc_cplr_ren & ~rc_cplr_q_ex[SOP])
        cpl_buf_wen_p1 <= #U_DLY 1'b1;
    else
        cpl_buf_wen_p1 <= #U_DLY 1'b0;
end
assign cpl_buf_wen = cpl_buf_wen_p1 | cpl_cover_one;
//always@(posedge user_clk )
//    cpl_buf_wen    <= (tag_legal_flg)? cpl_buf_wen_pre : 1'b0;


//偏移数据后，写侧比读侧少一拍标记
//generate if(DWIDTH==256)

//always@(posedge user_clk)
//begin
//  if(cpl_dw_cnt[2:0]==3'b0 || cpl_dw_cnt[2:0]>=3'd6)
//      cut_en <= 1'b1;
//  else
//      cut_en <= 1'b0;
//end

generate if(DWIDTH==256)
    assign cut_en = (cpl_dw_cnt[2:0]==3'b0 || cpl_dw_cnt[2:0]>=3'd6)? 1'b1 : 1'b0;
else if(DWIDTH==128)
    assign cut_en = (cpl_dw_cnt[1:0]==2'b0 || cpl_dw_cnt[1:0]>=2'd2)? 1'b1 : 1'b0;
endgenerate

//always@(posedge user_clk)
//begin
//    cut_en_1d <= cut_en;
//    cut_en_2d <= cut_en_1d;
//end

always @ ( posedge user_clk )
begin
    if ( ~cut_en & rc_cplr_ren_1d & rc_cplr_q_ex_1d[EOP] )
        cpl_cover_one <= #U_DLY 1'b1;
    else
        cpl_cover_one <= #U_DLY 1'b0;
end

always @ ( posedge user_clk )
begin
    if(rc_cplr_ren & rc_cplr_q_ex[EOP])
        rc_cplr_end <= #U_DLY 1'b1;
    else
        rc_cplr_end <= #U_DLY 1'b0;
end
always@(posedge user_clk)
    rc_cplr_end_1d <= rc_cplr_end;

//产生error信号
always @ ( posedge user_clk )
begin
    if(rc_cplr_ren & rc_cplr_q_ex[ERR])
        rc_cplr_err <= #U_DLY 1'b1;
    else
        rc_cplr_err <= #U_DLY 1'b0;
end

//always @ ( posedge user_clk )
//begin
////    if ( user_rst )
////        cpl_completed <= #U_DLY 1'b0;
////    else
//        cpl_completed <= #U_DLY cpl_head[30];
//end

//产生推迟一拍的尾信号
always @ ( posedge user_clk )
begin
    if( rc_cplr_end & cpl_completed )
        cpl_tag_wen_eop <= #U_DLY 1'b1;
    else
        cpl_tag_wen_eop <= #U_DLY 1'b0;
end



//always@(posedge user_clk)
//begin
//    if(user_rst)
//        cpl_buf_wadrs <= {(DATANUM_BIT+6){1'b0}};
//    else
//    begin
//        cpl_buf_wadrs[DATANUM_BIT+:6] <= cpl_tag[5:0];
//        if(cpl_tag_wen_eop)
//            cpl_buf_wadrs[0+:DATANUM_BIT] <= {DATANUM_BIT{1'b0}};
//        else if(cpl_buf_wen)
//            cpl_buf_wadrs[0+:DATANUM_BIT] <= cpl_buf_wadrs[0+:DATANUM_BIT] + 1'b1;
//        else
//            ;
//    end
//end
always@(posedge user_clk)
begin
    if(user_rst)
        cpl_tag_wadrs <= {DATANUM_BIT{1'b0}};
    else if(load_head_1d & cpl_tag!=cpl_tag_1d)
        cpl_tag_wadrs <= tag_wadrs[cpl_tag*DATANUM_BIT+:DATANUM_BIT];
    else if(cpl_buf_wen & tag_legal_flg)
        cpl_tag_wadrs <= cpl_tag_wadrs + 1'b1;
    else
        ;
end

//assign cpl_buf_wadrs = {cpl_tag_1d[5:0],tag_wadrs[cpl_tag_1d*DATANUM_BIT+:DATANUM_BIT]};
assign cpl_buf_wadrs = {cpl_tag_1d[5:0],cpl_tag_wadrs};


//=================================================
//  completion FSM
//=================================================

//读返回数据，分Tag缓存
sdp_ram #(
    .DATA_WIDTH     ( DWIDTH        ),
    .ADDR_WIDTH     ( DATANUM_BIT+6 ),
    .READ_LATENCY   ( 2             ),
    .MEMORY_TYPE    ( "auto"        )
)
u_CPL_BUF(
    .clka           ( user_clk      ),
    .addra          ( cpl_buf_wadrs ),
    .dina           ( cpl_buf_din   ),
    .wea            ( cpl_buf_wen   ),
    .clkb           ( user_clk      ),
    .addrb          ( cpl_buf_radrs ),
    .doutb          ( cpl_buf_dout  )
);




genvar  tag_i;
generate
    for ( tag_i = 0; tag_i < MAXTAG; tag_i = tag_i + 1)
    begin : gen_tag_i

    always@(posedge user_clk)
    begin
        if ( ~res_tag_init_done )
            tag_wadrs[tag_i*DATANUM_BIT+:DATANUM_BIT] <= {DATANUM_BIT{1'b0}};
        else if(cpl_tag_wen_eop & cpl_tag_1d==tag_i)
            tag_wadrs[tag_i*DATANUM_BIT+:DATANUM_BIT] <= {DATANUM_BIT{1'b0}};
        else if(rc_cplr_end_1d & cpl_tag_1d==tag_i)
            tag_wadrs[tag_i*DATANUM_BIT+:DATANUM_BIT] <= cpl_tag_wadrs;
        else
            ;
    end



    always @ ( posedge user_clk )
    begin
        if ( ~res_tag_init_done )
            cpl_tag_end_flg[tag_i] <= #U_DLY 1'b0;
        else if ( (cpl_tag_1d[7:0]==tag_i) & cpl_tag_wen_eop & tag_legal_flg)       //数据完全返回
            cpl_tag_end_flg[tag_i] <= #U_DLY 1'b1;
        else if ( (res_tag_rclm_din==tag_i) & res_tag_rclm_wen )    //tag 被回收，清除tag完成标记
            cpl_tag_end_flg[tag_i] <= #U_DLY 1'b0;
        else if( curr_r_retry & used_tag_curr==tag_i)
            cpl_tag_end_flg[tag_i] <= #U_DLY 1'b0;
        else
            ;
    end

    always @ ( posedge user_clk )
    begin
        if ( ~res_tag_init_done )
            cpl_tag_err[tag_i] <= #U_DLY 1'b0;
        else if ( (cpl_tag_1d[7:0]==tag_i) & rc_cplr_end_1d & tag_legal_flg)       //数据完全返回
            cpl_tag_err[tag_i] <= #U_DLY cpl_dw_err|cpl_tag_err[tag_i];
        else if ( (res_tag_rclm_din==tag_i) & res_tag_rclm_wen )    //tag 被回收，清除tag完成标记
            cpl_tag_err[tag_i] <= #U_DLY 1'b0;
        else if( curr_r_retry & used_tag_curr==tag_i)
            cpl_tag_err[tag_i] <= #U_DLY 1'b0;
        else
            ;
    end

    end
endgenerate

//根据Tag暂存对应的数据，写地址管理
generate if(MAXTAG==64) begin : gen_max_tag

    always @ ( posedge user_clk )
    begin
        case ( used_tag_next[5:0] )
        6'd0    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 0];
        6'd1    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 1];
        6'd2    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 2];
        6'd3    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 3];
        6'd4    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 4];
        6'd5    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 5];
        6'd6    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 6];
        6'd7    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 7];
        6'd8    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 8];
        6'd9    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 9];
        6'd10   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[10];
        6'd11   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[11];
        6'd12   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[12];
        6'd13   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[13];
        6'd14   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[14];
        6'd15   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[15];
        6'd16   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[16];
        6'd17   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[17];
        6'd18   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[18];
        6'd19   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[19];
        6'd20   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[20];
        6'd21   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[21];
        6'd22   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[22];
        6'd23   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[23];
        6'd24   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[24];
        6'd25   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[25];
        6'd26   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[26];
        6'd27   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[27];
        6'd28   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[28];
        6'd29   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[29];
        6'd30   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[30];
        6'd31   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[31];
        6'd32   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[32];
        6'd33   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[33];
        6'd34   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[34];
        6'd35   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[35];
        6'd36   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[36];
        6'd37   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[37];
        6'd38   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[38];
        6'd39   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[39];
        6'd40   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[40];
        6'd41   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[41];
        6'd42   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[42];
        6'd43   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[43];
        6'd44   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[44];
        6'd45   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[45];
        6'd46   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[46];
        6'd47   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[47];
        6'd48   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[48];
        6'd49   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[49];
        6'd50   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[50];
        6'd51   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[51];
        6'd52   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[52];
        6'd53   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[53];
        6'd54   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[54];
        6'd55   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[55];
        6'd56   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[56];
        6'd57   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[57];
        6'd58   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[58];
        6'd59   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[59];
        6'd60   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[60];
        6'd61   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[61];
        6'd62   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[62];
        default :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[63];
        endcase
    end

    always @ ( posedge user_clk )
    begin
        case ( used_tag_next[5:0] )
        6'd0    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 0];
        6'd1    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 1];
        6'd2    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 2];
        6'd3    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 3];
        6'd4    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 4];
        6'd5    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 5];
        6'd6    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 6];
        6'd7    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 7];
        6'd8    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 8];
        6'd9    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 9];
        6'd10   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[10];
        6'd11   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[11];
        6'd12   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[12];
        6'd13   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[13];
        6'd14   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[14];
        6'd15   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[15];
        6'd16   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[16];
        6'd17   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[17];
        6'd18   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[18];
        6'd19   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[19];
        6'd20   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[20];
        6'd21   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[21];
        6'd22   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[22];
        6'd23   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[23];
        6'd24   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[24];
        6'd25   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[25];
        6'd26   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[26];
        6'd27   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[27];
        6'd28   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[28];
        6'd29   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[29];
        6'd30   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[30];
        6'd31   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[31];
        6'd32   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[32];
        6'd33   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[33];
        6'd34   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[34];
        6'd35   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[35];
        6'd36   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[36];
        6'd37   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[37];
        6'd38   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[38];
        6'd39   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[39];
        6'd40   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[40];
        6'd41   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[41];
        6'd42   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[42];
        6'd43   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[43];
        6'd44   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[44];
        6'd45   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[45];
        6'd46   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[46];
        6'd47   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[47];
        6'd48   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[48];
        6'd49   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[49];
        6'd50   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[50];
        6'd51   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[51];
        6'd52   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[52];
        6'd53   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[53];
        6'd54   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[54];
        6'd55   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[55];
        6'd56   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[56];
        6'd57   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[57];
        6'd58   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[58];
        6'd59   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[59];
        6'd60   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[60];
        6'd61   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[61];
        6'd62   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[62];
        default :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[63];
        endcase
    end
end
else if(MAXTAG==32) begin

    always @ ( posedge user_clk )
    begin
        case ( used_tag_next[4:0] )
        5'd0    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 0];
        5'd1    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 1];
        5'd2    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 2];
        5'd3    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 3];
        5'd4    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 4];
        5'd5    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 5];
        5'd6    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 6];
        5'd7    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 7];
        5'd8    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 8];
        5'd9    :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[ 9];
        5'd10   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[10];
        5'd11   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[11];
        5'd12   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[12];
        5'd13   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[13];
        5'd14   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[14];
        5'd15   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[15];
        5'd16   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[16];
        5'd17   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[17];
        5'd18   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[18];
        5'd19   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[19];
        5'd20   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[20];
        5'd21   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[21];
        5'd22   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[22];
        5'd23   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[23];
        5'd24   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[24];
        5'd25   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[25];
        5'd26   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[26];
        5'd27   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[27];
        5'd28   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[28];
        5'd29   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[29];
        5'd30   :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[30];
        default :   cpl_tag_end_tmp <= #U_DLY cpl_tag_end_flg[31];
        endcase
    end

    always @ ( posedge user_clk )
    begin
        case ( used_tag_next[4:0] )
        5'd0    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 0];
        5'd1    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 1];
        5'd2    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 2];
        5'd3    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 3];
        5'd4    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 4];
        5'd5    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 5];
        5'd6    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 6];
        5'd7    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 7];
        5'd8    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 8];
        5'd9    :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[ 9];
        5'd10   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[10];
        5'd11   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[11];
        5'd12   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[12];
        5'd13   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[13];
        5'd14   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[14];
        5'd15   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[15];
        5'd16   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[16];
        5'd17   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[17];
        5'd18   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[18];
        5'd19   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[19];
        5'd20   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[20];
        5'd21   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[21];
        5'd22   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[22];
        5'd23   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[23];
        5'd24   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[24];
        5'd25   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[25];
        5'd26   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[26];
        5'd27   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[27];
        5'd28   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[28];
        5'd29   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[29];
        5'd30   :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[30];
        default :   cpl_tag_err_tmp <= #U_DLY cpl_tag_err[31];
        endcase
    end

end
endgenerate






always @ ( posedge user_clk )
begin
    if ( user_rst )
        jrsm_state <= #U_DLY R_IDLE;
    else
    begin
        case ( jrsm_state )
        R_IDLE  :   if ( tag_tout_flg )
                        jrsm_state <= #U_DLY R_RETRY;
                    else if ( cpl_tag_end_tmp)
                    begin
                        if(cpl_tag_err_tmp)
                            jrsm_state <= #U_DLY R_RETRY;
                        else if(iPcie_rx_ready)
                            jrsm_state <= #U_DLY R_READ;
                        else
                            jrsm_state <= #U_DLY R_IDLE;
                    end
                    else
                        jrsm_state <= #U_DLY R_IDLE;
        R_READ  :   if ( cpl_buf_ren_eop )
                        jrsm_state <= #U_DLY R_IDLE;
                    else
                        jrsm_state <= #U_DLY R_READ;
        R_RETRY :   if(retry_ack)
                        jrsm_state <= #U_DLY R_WAIT;
                    else
                        jrsm_state <= #U_DLY R_RETRY;
        R_WAIT  :   if(wait_dly)
                        jrsm_state <= #U_DLY R_IDLE;
                    else
                        jrsm_state <= #U_DLY R_WAIT;
        default :   jrsm_state <= #U_DLY R_IDLE;
        endcase
    end
end

assign curr_r_idle = jrsm_state[0];
assign curr_r_read = jrsm_state[1];
assign curr_r_retry= jrsm_state[2];
assign curr_r_wait = jrsm_state[3];

always@(posedge user_clk)
begin
    if(curr_r_wait)
        wait_dly <= ~wait_dly;
    else
        wait_dly <= 1'b0;
end

assign cpl_buf_ren = curr_r_read ;
assign cpl_buf_ren_sop = curr_r_read & (cpl_cnt == {DATANUM_BIT{1'b0}});
assign cpl_buf_ren_eop = curr_r_read & (cpl_cnt == cpl_num) ;

assign len = used_tag_dout[79:64];
assign offset = used_tag_dout[BEATWIDTH_BIT-1:0];


always @ ( posedge user_clk )
begin
    if( curr_r_idle )
    begin
        if(cpl_tag_end_tmp)
            tag_flg <= 2'b10;
        else if(tag_tout_flg)
            tag_flg <= 2'b01;
        else
            tag_flg <= 2'b00;
    end
    else
        ;
end
always @ ( posedge user_clk )
begin
    if( curr_r_idle )
        used_tag_dout_1d <= used_tag_dout;
    else
        ;
end
assign cpl_sop = used_tag_dout_1d[143];
assign cpl_eop = used_tag_dout_1d[142];
assign cpl_offset = used_tag_dout_1d[BEATWIDTH_BIT-1:0];
assign cpl_len = used_tag_dout_1d[79:64];

always @ ( posedge user_clk )
    cpl_offset_1d <= cpl_offset;

//always @ ( posedge user_clk )
//    cpl_len_1d <= #U_DLY cpl_len;

assign cpl_addr_end = len[MAXREADREQ_BIT-1:0] + {{(MAXREADREQ_BIT-BEATWIDTH_BIT){1'b0}},offset};

//start or end cpld
always @ ( posedge user_clk )
begin
    if( curr_r_idle )
        cpl_num_s <= #U_DLY (len[BEATWIDTH_BIT-1:0]=={BEATWIDTH_BIT{1'b0}})? len[MAXREADREQ_BIT-1:BEATWIDTH_BIT] - 1'b1 :
                                                                             len[MAXREADREQ_BIT-1:BEATWIDTH_BIT];
    else
        ;
end
//middle cpld
assign cpl_num_m = {DATANUM_BIT{1'b1}};
//start and end cpld
always @ ( posedge user_clk )
begin
    if( curr_r_idle )
        cpl_num_sl <= #U_DLY (cpl_addr_end[BEATWIDTH_BIT-1:0]=={BEATWIDTH_BIT{1'b0}})? cpl_addr_end[MAXREADREQ_BIT-1:BEATWIDTH_BIT] - 1'b1 :
                                                                                       cpl_addr_end[MAXREADREQ_BIT-1:BEATWIDTH_BIT];
    else
        ;
end
assign cpl_num = (cpl_sop & cpl_eop)?     cpl_num_sl :
                 (~cpl_sop & ~cpl_eop)?   cpl_num_m  : cpl_num_s;

always @ ( posedge user_clk )
    cpl_sop_1d <= #U_DLY cpl_sop;

always @ ( posedge user_clk )
    cpl_eop_1d <= #U_DLY cpl_eop;

always @ ( posedge user_clk )
begin
    if ( rx_cpl_wen_sop )
        cpl_sop_offset <= #U_DLY cpl_offset_1d;
    else
        ;
end



always @ ( posedge user_clk )
begin
    if ( cpl_buf_ren_eop )
        cpl_whole_len <= #U_DLY cpl_sop?   cpl_len : cpl_whole_len + cpl_len;
    else
        ;
end

always @ ( posedge user_clk )
begin
    if ( cpl_buf_ren_eop & cpl_sop )
        cpl_start_adrs <= #U_DLY used_tag_dout_1d[63:0];
    else
        ;
end

always @ ( posedge user_clk )
begin
    if ( cpl_buf_ren_eop & cpl_sop )
        cpl_start_info <= #U_DLY used_tag_dout_1d[139:96];
    else
        ;
end

always @ ( posedge user_clk )
begin
    if ( cpl_buf_ren_eop & cpl_sop )
        cpl_rid <= #U_DLY used_tag_dout_1d[87:80];
    else
        ;
end

always @ ( posedge user_clk )
begin
    if ( user_rst )
        cpl_cnt <= #U_DLY {DATANUM_BIT{1'b0}};
    else if ( cpl_buf_ren_eop )
        cpl_cnt <= #U_DLY {DATANUM_BIT{1'b0}};
    else if ( cpl_buf_ren )
        cpl_cnt <= #U_DLY cpl_cnt + 1'b1;
    else
        ;
end



////指示数据包错误
//always @ ( posedge user_clk )
//begin
//    if ( cpl_buf_ren_eop )
//        cpl_pkt_err <= #U_DLY (tag_flg==2'b01)? 1'b1 :
//                              (cpl_sop==1'b1)?  cpl_tag_err_tmp :
//                                                (cpl_pkt_err|cpl_tag_err_tmp);
//    else
//        ;
//end

always@(posedge user_clk )
begin
    if(cpl_buf_ren_eop & (tag_flg==2'b01))
        tag_tout_pulse <= 1'b1;
    else
        tag_tout_pulse <= 1'b0;
end

always @ ( posedge user_clk )
begin
    cpl_buf_ren_1d <= #U_DLY cpl_buf_ren;
    cpl_buf_ren_2d <= #U_DLY cpl_buf_ren_1d;
end
always @ ( posedge user_clk )
    cpl_buf_ren_sop_1d <= #U_DLY cpl_buf_ren_sop;

always @ ( posedge user_clk )
    cpl_buf_ren_eop_1d <= #U_DLY cpl_buf_ren_eop;



always @ ( posedge user_clk )
begin
    if ( cpl_buf_ren_2d )
        cpl_buf_dout_1d <= #U_DLY cpl_buf_dout;
    else
        ;
end


//移位后会减少一拍写操作的标志
assign cpl_last_len = {1'b0,cpl_whole_len[BEATWIDTH_BIT-1:0]} + {1'b0,cpl_sop_offset};
always @ ( posedge user_clk )
begin
    if ( rx_cpl_wen_eop )
    begin
        if( rx_cpl_wen_sop )
            cpl_nocut_en <= #U_DLY 1'b1;
        else if(cpl_whole_len[BEATWIDTH_BIT-1:0]=={BEATWIDTH_BIT{1'b0}})
            cpl_nocut_en <= #U_DLY (cpl_sop_offset=={BEATWIDTH_BIT{1'b0}})? 1'b1 : 1'b0;
        else
            cpl_nocut_en <= #U_DLY (cpl_last_len<={1'b1,{BEATWIDTH_BIT{1'b0}}})? 1'b1 : 1'b0;
    end
    else
        cpl_nocut_en <= #U_DLY 1'b0;
end

always @ ( posedge user_clk )
    cpl_nocut_en_1d <= #U_DLY cpl_nocut_en;

always @ ( posedge user_clk )
begin
    if ( user_rst )
        rx_cpl_wen <= #U_DLY 1'b0;
    else if( cpl_buf_ren_1d )
        rx_cpl_wen <= #U_DLY (rx_cpl_wen_sop)? 1'b0 : 1'b1;
    else
        rx_cpl_wen <= #U_DLY 1'b0;
end

assign rx_cpl_wen_sop = cpl_buf_ren_sop_1d & cpl_sop_1d ;
assign rx_cpl_wen_eop = cpl_buf_ren_eop_1d & cpl_eop_1d ;


//always @ ( posedge user_clk )
//    rx_cpl_wen_sop_1d <= #U_DLY rx_cpl_wen_sop;

always @ ( posedge user_clk )
begin
    rx_cpl_wen_eop_1d <= #U_DLY rx_cpl_wen_eop;
    rx_cpl_wen_eop_2d <= #U_DLY rx_cpl_wen_eop_1d;
end
always @ ( posedge user_clk )
    cpl_whole_len_1d <= #U_DLY cpl_whole_len;
always @ ( posedge user_clk )
    cpl_start_adrs_1d <= #U_DLY cpl_start_adrs;
always @ ( posedge user_clk )
    cpl_start_info_1d <= #U_DLY cpl_start_info;
always @ ( posedge user_clk )
    cpl_rid_1d <= #U_DLY cpl_rid;


//always @ ( posedge user_clk )
//    cpl_pkt_err_1d <= #U_DLY cpl_pkt_err;

//retry operation
assign retry_tag  = used_tag_curr;
assign retry_data = used_tag_dout_1d;
assign retry_req  = curr_r_retry;




generate if(DWIDTH==256)
begin
    always @ ( posedge user_clk )// )
    begin
        case ( cpl_sop_offset )
        5'd0    :   oPcie_rx_datain <= #U_DLY {                      cpl_buf_dout_1d[255:  0] };
        5'd1    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[  7:0], cpl_buf_dout_1d[255:  8] } ;
        5'd2    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 15:0], cpl_buf_dout_1d[255: 16] } ;
        5'd3    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 23:0], cpl_buf_dout_1d[255: 24] } ;
        5'd4    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 31:0], cpl_buf_dout_1d[255: 32] } ;
        5'd5    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 39:0], cpl_buf_dout_1d[255: 40] } ;
        5'd6    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 47:0], cpl_buf_dout_1d[255: 48] } ;
        5'd7    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 55:0], cpl_buf_dout_1d[255: 56] } ;
        5'd8    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 63:0], cpl_buf_dout_1d[255: 64] } ;
        5'd9    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 71:0], cpl_buf_dout_1d[255: 72] } ;
        5'd10   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 79:0], cpl_buf_dout_1d[255: 80] } ;
        5'd11   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 87:0], cpl_buf_dout_1d[255: 88] } ;
        5'd12   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 95:0], cpl_buf_dout_1d[255: 96] } ;
        5'd13   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[103:0], cpl_buf_dout_1d[255:104] } ;
        5'd14   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[111:0], cpl_buf_dout_1d[255:112] } ;
        5'd15   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[119:0], cpl_buf_dout_1d[255:120] } ;
        5'd16   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[127:0], cpl_buf_dout_1d[255:128] } ;
        5'd17   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[135:0], cpl_buf_dout_1d[255:136] } ;
        5'd18   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[143:0], cpl_buf_dout_1d[255:144] } ;
        5'd19   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[151:0], cpl_buf_dout_1d[255:152] } ;
        5'd20   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[159:0], cpl_buf_dout_1d[255:160] } ;
        5'd21   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[167:0], cpl_buf_dout_1d[255:168] } ;
        5'd22   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[175:0], cpl_buf_dout_1d[255:176] } ;
        5'd23   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[183:0], cpl_buf_dout_1d[255:184] } ;
        5'd24   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[191:0], cpl_buf_dout_1d[255:192] } ;
        5'd25   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[199:0], cpl_buf_dout_1d[255:200] } ;
        5'd26   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[207:0], cpl_buf_dout_1d[255:208] } ;
        5'd27   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[215:0], cpl_buf_dout_1d[255:216] } ;
        5'd28   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[223:0], cpl_buf_dout_1d[255:224] } ;
        5'd29   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[231:0], cpl_buf_dout_1d[255:232] } ;
        5'd30   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[239:0], cpl_buf_dout_1d[255:240] } ;
        default :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[247:0], cpl_buf_dout_1d[255:248] } ;
        endcase
    end
end
else if(DWIDTH==128)
begin
    always @ ( posedge user_clk )// )
    begin
        case ( cpl_sop_offset )
        4'd0    :   oPcie_rx_datain <= #U_DLY {                      cpl_buf_dout_1d[127:  0] };
        4'd1    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[  7:0], cpl_buf_dout_1d[127:  8] } ;
        4'd2    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 15:0], cpl_buf_dout_1d[127: 16] } ;
        4'd3    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 23:0], cpl_buf_dout_1d[127: 24] } ;
        4'd4    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 31:0], cpl_buf_dout_1d[127: 32] } ;
        4'd5    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 39:0], cpl_buf_dout_1d[127: 40] } ;
        4'd6    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 47:0], cpl_buf_dout_1d[127: 48] } ;
        4'd7    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 55:0], cpl_buf_dout_1d[127: 56] } ;
        4'd8    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 63:0], cpl_buf_dout_1d[127: 64] } ;
        4'd9    :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 71:0], cpl_buf_dout_1d[127: 72] } ;
        4'd10   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 79:0], cpl_buf_dout_1d[127: 80] } ;
        4'd11   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 87:0], cpl_buf_dout_1d[127: 88] } ;
        4'd12   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[ 95:0], cpl_buf_dout_1d[127: 96] } ;
        4'd13   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[103:0], cpl_buf_dout_1d[127:104] } ;
        4'd14   :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[111:0], cpl_buf_dout_1d[127:112] } ;
        default :   oPcie_rx_datain <= #U_DLY { cpl_buf_dout[119:0], cpl_buf_dout_1d[127:120] } ;
        endcase
    end
end
endgenerate


always @ ( posedge user_clk )
begin
    if ( user_rst )
        oPcie_rx_wrreq <= #U_DLY 1'b0;
    else if ( rx_cpl_wen | cpl_nocut_en_1d)
        oPcie_rx_wrreq <= #U_DLY 1'b1;
    else
        oPcie_rx_wrreq <= #U_DLY 1'b0;
end

always @ ( posedge user_clk)
begin
    if ( rx_cpl_wen_eop_1d )
        oPcie_rx_headin <= #U_DLY {2'b11,
                                   1'b0,
                                   1'b0,
                                   cpl_start_info_1d[43:0],
                                   3'b0,
                                   5'b0,cpl_rid_1d,
                                   cpl_whole_len_1d,
                                   cpl_start_adrs_1d};
    else
        ;
end

always @ ( posedge user_clk )
begin
    if ( user_rst )
        oPcie_rx_Hwrreq <= #U_DLY 1'b0;
    else if ( (rx_cpl_wen_eop_2d & cpl_nocut_en_1d) | (rx_cpl_wen_eop_1d & ~cpl_nocut_en) )
        oPcie_rx_Hwrreq <= #U_DLY 1'b1;
    else
        oPcie_rx_Hwrreq <= #U_DLY 1'b0;
end

always @ ( posedge user_clk )
begin
    if ( user_rst )
        used_tag_curr <= #U_DLY 8'b0;
    else if ( ~res_tag_init_done )
        used_tag_curr <= #U_DLY 8'b0;
    else if ( cpl_buf_ren_eop )
        used_tag_curr <= #U_DLY used_tag_next;
    else
        ;
end
always @ ( posedge user_clk )
begin
    if ( user_rst )
        used_tag_next <= #U_DLY 8'b0;
    else if ( ~res_tag_init_done )
        used_tag_next <= #U_DLY 8'b0;
    else if(curr_r_idle & (cpl_tag_end_tmp & ~cpl_tag_err_tmp) & iPcie_rx_ready)
    begin
        used_tag_next[7:MAXTAG_BIT] <= #U_DLY {(8-MAXTAG_BIT){1'b0}};
        used_tag_next[MAXTAG_BIT-1:0] <= #U_DLY used_tag_curr[MAXTAG_BIT-1:0] + 1'b1;
    end
end
//always@(posedge user_clk)
//  user_tag_next_1d <= user_tag_next;


assign used_tag_radrs[5:0] = used_tag_next[5:0];




//数据包被从Tag缓存里读出，回收Tag信息
//always @ ( posedge user_clk )
//begin
//    if ( cpl_buf_ren_eop )
//        res_tag_rclm_din <= #U_DLY used_tag_curr;
//    else
//        ;
//end
//
//always @ ( posedge user_clk )
//begin
//    if ( user_rst )
//        res_tag_rclm_wen <= #U_DLY 1'b0;
//    else if ( cpl_buf_ren_eop )
//        res_tag_rclm_wen <= #U_DLY 1'b1;
//    else
//        res_tag_rclm_wen <= #U_DLY 1'b0;
//end
assign res_tag_rclm_din = used_tag_curr;
assign res_tag_rclm_wen = cpl_buf_ren_eop;


assign cpl_buf_radrs = {used_tag_curr[5:0],cpl_buf_radrs_l};
always @ ( posedge user_clk )
begin
    if ( user_rst )
        cpl_buf_radrs_l <= #U_DLY {DATANUM_BIT{1'b0}};
    else if ( cpl_buf_ren_eop )
        cpl_buf_radrs_l <= #U_DLY {DATANUM_BIT{1'b0}};
    else if ( cpl_buf_ren )
        cpl_buf_radrs_l <= #U_DLY cpl_buf_radrs_l + 1'b1;
    else
        ;
end


endmodule
