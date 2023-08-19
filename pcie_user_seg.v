
`timescale 100ps / 1ps
module pcie_user_seg #(
parameter   MAXPAYLOAD  = 256,          //option 7/8/9
parameter   MAXREADREQ  = 512,
parameter   DWIDTH      = 256
)(
// ===========================================================================
//part0: port singal define
// ===========================================================================
input                   user_clk            ,
input                   user_rst            ,

input                   iPcie_OPEN          ,
output      [15: 0]     odbg_info           ,

input                   iPcie_seg_ready     ,       //按256byte为分片形式送出
output      [143:0]     oPcie_seg_headin    ,
output                  oPcie_seg_Hwrreq    ,
output      [DWIDTH-1:0]oPcie_seg_datain    ,
output                  oPcie_seg_wrreq     ,

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


    //用户侧请求类型,格式定义
localparam  REQ_TYPE_MWR    = 3'b000    ;
localparam  REQ_TYPE_MRD    = 3'b010    ;
localparam  REQ_TYPE_INT    = 3'b110    ;
localparam  REQ_TYPE_ATS    = 3'b001    ;

    //descriptor请求类型定义
localparam  TLP_MRD         = 4'b0000   ;
localparam  TLP_MWR         = 4'b0001   ;
localparam  TLP_ATS         = 4'b1110   ;



//write data buffer control signal

//write data buffer data and status signal
wire                            jPcie_tx_empty          ;
wire                            jPcie_tx_Hrdreq         ;
wire                            jPcie_tx_rdreq          ;
wire    [143:0]                 jPcie_tx_headout        ;
wire    [DWIDTH-1:0]            jPcie_tx_dataout        ;
reg     [DWIDTH-1:0]            jPcie_tx_dataout_1d     ;

wire                            jPcie_rd_rdreq          ;

//segment output
reg     [143:0]                 jPcie_seg_headin        ;
reg                             jPcie_seg_Hwrreq        ;
reg     [DWIDTH-1:0]            jPcie_seg_datain        ;
reg                             jPcie_seg_wrreq         ;

//fsm
reg     [ 2: 0]                 jseg_state              ;   //fsm
wire                            curr_idle               ;   //idle state
wire                            curr_mwr                ;   //mwr state
wire                            curr_drop               ;   //drop state

reg     [DATANUM_BIT-1:0]       jseg_statecnt           ;   //mwr state cycle cnt

wire                            load_head               ;   //loading head
reg     [ 7: 0]                 seg_num                 ;   //the segment number for one packet
reg     [ 7: 0]                 seg_cnt                 ;   //the cycle cnt for one segment

//wire    [ 7: 0]                 seq_id                  ;   //sequence num
//reg     [ 7: 0]                 seq_id_1d               ;
//reg     [ 7: 0]                 seq_id_2d               ;
wire                            req_type                ;
reg                             req_type_1d             ;
reg                             req_type_2d             ;
wire    [43: 0]                 req_info                ;
reg     [43: 0]                 req_info_1d             ;
reg     [43: 0]                 req_info_2d             ;
wire    [ 7: 0]                 rid                     ;   //request id
reg     [ 7: 0]                 rid_1d                  ;   //
reg     [ 7: 0]                 rid_2d                  ;
wire                            head_err                ;   //error packet

wire    [63: 0]                 req_start_addr          ;   //write start address
wire    [63: 0]                 req_end_addr            ;   //write end address
wire                            req_end_addr_and        ;
wire    [BEATWIDTH_BIT-1:0]     req_offset              ;   //offset in 32byte unit
reg     [BEATWIDTH_BIT-1:0]     req_offset_1d           ;
reg     [BEATWIDTH_BIT-1:0]     req_offset_2d           ;
wire    [15: 0]                 req_length              ;   //write length
wire    [15: 0]                 req_addr_end_tmp        ;

reg     [15: 0]                 req_curr_len_f          ;   //first operation len
wire    [15: 0]                 req_curr_len_m          ;   //middle operation len
reg     [15: 0]                 req_curr_len_l          ;   //last operation len
reg     [15: 0]                 req_curr_len_fl         ;   //first and last operation len
wire    [15: 0]                 req_curr_len            ;   //actual operation length
reg     [15: 0]                 req_curr_len_1d         ;
reg     [15: 0]                 req_curr_len_2d         ;
reg     [DATANUM_BIT-1:0]       req_rd_num_f            ;   //first operation beat
wire    [DATANUM_BIT-1:0]       req_rd_num_m            ;   //middle operation beat
reg     [DATANUM_BIT-1:0]       req_rd_num_l            ;   //last operation beat
reg     [DATANUM_BIT-1:0]       req_rd_num_fl           ;   //first and last operation beat
wire    [DATANUM_BIT-1:0]       req_rd_num              ;   //actual operation beat


reg                             req_op_sop              ;   //sop indicate
reg                             req_op_sop_1d           ;
(* max_fanout = 100 *)
reg                             req_op_sop_2d           ;
wire                            req_op_eop              ;   //eop indicate
reg                             req_op_eop_1d           ;
reg                             req_op_eop_2d           ;

reg     [63: 0]                 seg_start_addr          ;   //segment operation start address
reg     [63: 0]                 seg_start_addr_1d       ;
reg     [63: 0]                 seg_start_addr_2d       ;


reg                             jPcie_tx_rdreq_1d       ;
reg                             jPcie_tx_rdreq_2d       ;


wire                            jPcie_tx_rdreq_eop      ;   //segment operation end beat
reg                             jPcie_tx_rdreq_eop_1d   ;
reg                             jPcie_tx_rdreq_eop_2d   ;
wire                            drop_errType            ;


reg     [ 7: 0]                 jdrop_cnt               ;
// ===========================================================================
//
// ===========================================================================
localparam   S_IDLE     = 3'b001    ;   //空闲状态,计算切片
localparam   S_MWR      = 3'b010    ;   //写分片数据状态
localparam   S_DROP     = 3'b100    ;


assign odbg_info = {jdrop_cnt,1'b0,iPcie_seg_ready,oPcie_tx_ready,jPcie_tx_empty,1'b0,jseg_state};
always @ ( posedge user_clk )
begin
    if ( user_rst )
        jdrop_cnt <= #U_DLY 8'b0;
    else if( drop_errType )
        jdrop_cnt <= #U_DLY jdrop_cnt + 1'b1;
    else
        ;
end


//Soft_reset transfer Clock Region to sync

//=============================================================================================
//PCIE x4 Gen1 port
//=============================================================================================
//每个head附带的数据为2Kbyte
//减小逻辑内部的数据包缓存能力，保证数据包比消息先被写入到内存中

muti_func_fifo #(
    .LONGBUF    ( 0         ),
    .DWIDTH     ( DWIDTH    ),
    .HWIDTH     ( 144       )
)
u_muti_func_fifo(
    .user_clk           ( user_clk  ),
    .user_rst           ( user_rst  ),

    .oInfo_ready        ( oPcie_tx_ready    ),
    .iInfo_headin       ( iPcie_tx_headin   ),
    .iInfo_Hwrreq       ( iPcie_tx_Hwrreq   ),
    .iInfo_datain       ( iPcie_tx_datain   ),
    .iInfo_wrreq        ( iPcie_tx_wrreq    ),

    .oInfo_empty        ( jPcie_tx_empty    ),
    .oInfo_headout      ( jPcie_tx_headout  ),
    .iInfo_Hrdreq       ( jPcie_tx_Hrdreq   ),
    .oInfo_dataout      ( jPcie_tx_dataout  ),
    .iInfo_rdreq        ( jPcie_tx_rdreq    ),
    .iInfo_Hrdreq_ag    ( 1'b0              ),
    .ostate_dbg         ( )
);



//===========================================================================
//  Read side
//===========================================================================
//choice the channal
//保存head信息的Ram读操作到数据有效需要延迟一拍，将空信号打拍用于后级模块在看到空就可以直接获取头信息

assign load_head = ~jPcie_tx_empty & curr_idle;

//assign seq_id   = jPcie_tx_headout[151:144];
assign head_err = jPcie_tx_headout[141];    //head被打上了error标志

assign req_type       = (jPcie_tx_headout[95:93]==REQ_TYPE_MWR)? 1'b0 : 1'b1;
assign req_info       = jPcie_tx_headout[139:96];
assign rid            = jPcie_tx_headout[87:80];
assign req_start_addr = jPcie_tx_headout[63:0];
assign req_offset     = req_start_addr[BEATWIDTH_BIT-1:0];
assign req_length     = jPcie_tx_headout[79:64];

assign req_end_addr[63:0] = req_start_addr[63:0] + {48'b0,req_length};

//===========================================================================
//  判断是否越界，并计算每次操作的地址及长度，firstBE及lastBE
//===========================================================================
always @ ( posedge user_clk )
begin
    if( load_head & ~req_type)
    begin
        if(req_length==16'b0)
            seg_num <= #U_DLY 8'b0;
        else if(req_end_addr[MAXPAYLOAD_BIT-1:0]=={MAXPAYLOAD_BIT{1'b0}})
            seg_num <= #U_DLY req_end_addr[MAXPAYLOAD_BIT+:8] - req_start_addr[MAXPAYLOAD_BIT+:8] - 1'b1;
        else
            seg_num <= #U_DLY req_end_addr[MAXPAYLOAD_BIT+:8] - req_start_addr[MAXPAYLOAD_BIT+:8];
    end
    else if( load_head)
    begin
        if(req_length==16'b0)
            seg_num <= #U_DLY 8'b0;
        else if(req_end_addr[MAXREADREQ_BIT-1:0]=={MAXREADREQ_BIT{1'b0}})
            seg_num <= #U_DLY req_end_addr[MAXREADREQ_BIT+:8] - req_start_addr[MAXREADREQ_BIT+:8] - 1'b1;
        else
            seg_num <= #U_DLY req_end_addr[MAXREADREQ_BIT+:8] - req_start_addr[MAXREADREQ_BIT+:8];
    end
    else
        ;
end

always @ ( posedge user_clk )
begin
    if( load_head )
        seg_cnt <= #U_DLY 8'b0;
    else if(jPcie_tx_rdreq_eop)
        seg_cnt <= #U_DLY seg_cnt + 1'b1;
    else
        ;
end

//generate every segment write operation address
//每个切片的操作起始地址
always@*
begin
    if(~req_type)
    begin
        seg_start_addr[63:MAXPAYLOAD_BIT]  = (req_op_sop)? req_start_addr[63:MAXPAYLOAD_BIT]  : (req_start_addr[63:MAXPAYLOAD_BIT] + seg_cnt);
        seg_start_addr[MAXPAYLOAD_BIT-1:0] = (req_op_sop)? req_start_addr[MAXPAYLOAD_BIT-1:0] : {MAXPAYLOAD_BIT{1'b0}};
    end
    else
    begin
        seg_start_addr[63:MAXREADREQ_BIT]  = (req_op_sop)? req_start_addr[63:MAXREADREQ_BIT]  : (req_start_addr[63:MAXREADREQ_BIT] + seg_cnt);
        seg_start_addr[MAXREADREQ_BIT-1:0] = (req_op_sop)? req_start_addr[MAXREADREQ_BIT-1:0] : {MAXREADREQ_BIT{1'b0}};
    end
end


//current length of every slice
always @ ( posedge user_clk )
begin
    if ( load_head )
    begin
        if(~req_type)
            req_curr_len_f <= #U_DLY MAXPAYLOAD - { {(16-MAXPAYLOAD_BIT){1'b0}},req_start_addr[MAXPAYLOAD_BIT-1:0] } ;
        else
            req_curr_len_f <= #U_DLY MAXREADREQ - { {(16-MAXREADREQ_BIT){1'b0}},req_start_addr[MAXREADREQ_BIT-1:0] } ;
    end
    else
        ;
end
assign req_curr_len_m = (~req_type)? MAXPAYLOAD : MAXREADREQ;
always @ ( posedge user_clk )
begin
    if ( load_head )    //calc current slice length for write operation
    begin
        if(~req_type)
            req_curr_len_l <= #U_DLY (req_end_addr[MAXPAYLOAD_BIT-1:0]=={MAXPAYLOAD_BIT{1'b0}})? MAXPAYLOAD : {{(16-MAXPAYLOAD_BIT){1'b0}},req_end_addr[MAXPAYLOAD_BIT-1:0]} ;
        else
            req_curr_len_l <= #U_DLY (req_end_addr[MAXREADREQ_BIT-1:0]=={MAXREADREQ_BIT{1'b0}})? MAXREADREQ : {{(16-MAXREADREQ_BIT){1'b0}},req_end_addr[MAXREADREQ_BIT-1:0]} ;
    end
    else
        ;
end
always @ ( posedge user_clk )
begin
    if ( load_head )
        req_curr_len_fl <= #U_DLY req_length;
    else
        ;
end
assign req_curr_len = ( req_op_sop & req_op_eop )? req_curr_len_fl :
                      ( req_op_sop )?              req_curr_len_f  :
                      ( req_op_eop )?              req_curr_len_l  :
                                                   req_curr_len_m;


//考虑起始地址和实际数据包长度
assign req_addr_end_tmp = req_length + req_start_addr[1:0];
assign req_end_addr_and = ~(|req_end_addr[BEATWIDTH_BIT-1:0]);
//实际读上级缓存的拍数,用于写操作
always @ ( posedge user_clk )
begin
    if ( load_head )    //写操作时，区分尾切片和非尾切片
        req_rd_num_f <= #U_DLY (MAXPAYLOAD*8/DWIDTH - 1'b1) - req_start_addr[MAXPAYLOAD_BIT-1:BEATWIDTH_BIT] ;  //判断需要操作的长度与剩余空间的大小
    else
        ;
end
assign req_rd_num_m = MAXPAYLOAD*8/DWIDTH - 1'b1;
always @ ( posedge user_clk )
begin
    if ( load_head )    //写操作时，区分尾切片和非尾切片
        req_rd_num_l <= #U_DLY req_end_addr[MAXPAYLOAD_BIT-1:BEATWIDTH_BIT] - {{(MAXPAYLOAD_BIT-BEATWIDTH_BIT-1){1'b0}},req_end_addr_and} ;  //判断需要操作的长度与剩余空间的大小
    else
        ;
end
always @ ( posedge user_clk )
begin
    if ( load_head )
        req_rd_num_fl <= #U_DLY (req_addr_end_tmp[BEATWIDTH_BIT-1:0]=={(BEATWIDTH_BIT){1'b0}})? req_addr_end_tmp[MAXPAYLOAD_BIT-1:BEATWIDTH_BIT] - 1'b1 : req_addr_end_tmp[MAXPAYLOAD_BIT-1:BEATWIDTH_BIT];
    else
        ;
end
assign req_rd_num = ( req_op_sop & req_op_eop )? req_rd_num_fl :
                    ( req_op_sop )?              req_rd_num_f  :
                    ( req_op_eop )?              req_rd_num_l  :
                                                 req_rd_num_m;

//对于整个数据包来说的首切片标志
always@*
begin
    if(~req_type)
        req_op_sop = (seg_cnt=={(16-MAXPAYLOAD_BIT){1'b0}})? 1'b1 : 1'b0;
    else
        req_op_sop = (seg_cnt=={(16-MAXREADREQ_BIT){1'b0}})? 1'b1 : 1'b0;
end
//对于整个数据包来说的尾切片标志
assign req_op_eop = (seg_cnt==seg_num)? 1'b1 : 1'b0;


//===============================================
//  状态机
//===============================================

//计算一个数据包以128bit为单位的长度大小,用于分256byte读写操作
always @ ( posedge user_clk )
begin
    if ( curr_mwr )
        jseg_statecnt <= #U_DLY (jPcie_tx_rdreq_eop)? {DATANUM_BIT{1'b0}}  :
                                (jPcie_tx_rdreq )?    jseg_statecnt + 1'b1 :
                                                      jseg_statecnt;
    else
        jseg_statecnt <= #U_DLY {DATANUM_BIT{1'b0}};
end

//FSM
always @ ( posedge user_clk )
begin
    if ( user_rst )
        jseg_state <= #U_DLY S_IDLE ;
    else
    begin
        case ( jseg_state )
        S_IDLE  :   if ( iPcie_OPEN & ~jPcie_tx_empty & head_err )
                        jseg_state <= #U_DLY S_DROP ;
                    else if ( iPcie_OPEN & ~jPcie_tx_empty )
                        jseg_state <= #U_DLY iPcie_seg_ready? S_MWR : S_IDLE;
                    else
                        jseg_state <= #U_DLY S_IDLE ;
        S_MWR   :   if ( jPcie_tx_Hrdreq )
                        jseg_state <= #U_DLY S_IDLE ;
                    else
                        jseg_state <= #U_DLY S_MWR ;
        S_DROP  :   jseg_state <= #U_DLY S_IDLE ;
        default :   jseg_state <= #U_DLY S_IDLE ;
        endcase
    end
end

assign curr_idle  = jseg_state[0] & iPcie_OPEN;
assign curr_mwr   = jseg_state[1];
assign curr_drop  = jseg_state[2];





//type类型非法/head error，丢弃该数据
assign drop_errType = curr_drop;

assign jPcie_tx_rdreq  = curr_mwr & ~req_type & iPcie_seg_ready;
assign jPcie_rd_rdreq  = curr_mwr & req_type & iPcie_seg_ready;
//slice end
assign jPcie_tx_rdreq_eop =  jPcie_tx_rdreq & (jseg_statecnt==req_rd_num) | jPcie_rd_rdreq;
//last slice and end
assign jPcie_tx_Hrdreq = ( req_op_eop & jPcie_tx_rdreq_eop ) | drop_errType;


//数据偏移
generate if(DWIDTH==512)
    always @ ( posedge user_clk )
    begin
        if(req_op_sop_2d)
        begin
            case ( req_offset_2d[1:0] )
            2'd0    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*64] } ;
            2'd1    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*63], jPcie_tx_dataout_1d[511:8*63] } ;
            2'd2    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*62], jPcie_tx_dataout_1d[511:8*62] } ;
            default :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*61], jPcie_tx_dataout_1d[511:8*61] } ;
            endcase
        end
        else
        begin
            case ( req_offset_2d )       //实际物理地址的偏移
            6'd0    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*64] } ;
            6'd1    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*63], jPcie_tx_dataout_1d[511:8*63] } ;
            6'd2    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*62], jPcie_tx_dataout_1d[511:8*62] } ;
            6'd3    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*61], jPcie_tx_dataout_1d[511:8*61] } ;
            6'd4    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*60], jPcie_tx_dataout_1d[511:8*60] } ;
            6'd5    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*59], jPcie_tx_dataout_1d[511:8*59] } ;
            6'd6    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*58], jPcie_tx_dataout_1d[511:8*58] } ;
            6'd7    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*57], jPcie_tx_dataout_1d[511:8*57] } ;
            6'd8    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*56], jPcie_tx_dataout_1d[511:8*56] } ;
            6'd9    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*55], jPcie_tx_dataout_1d[511:8*55] } ;
            6'd10   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*54], jPcie_tx_dataout_1d[511:8*54] } ;
            6'd11   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*53], jPcie_tx_dataout_1d[511:8*53] } ;
            6'd12   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*52], jPcie_tx_dataout_1d[511:8*52] } ;
            6'd13   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*51], jPcie_tx_dataout_1d[511:8*51] } ;
            6'd14   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*50], jPcie_tx_dataout_1d[511:8*50] } ;
            6'd15   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*49], jPcie_tx_dataout_1d[511:8*49] } ;
            6'd16   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*48], jPcie_tx_dataout_1d[511:8*48] } ;
            6'd17   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*47], jPcie_tx_dataout_1d[511:8*47] } ;
            6'd18   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*46], jPcie_tx_dataout_1d[511:8*46] } ;
            6'd19   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*45], jPcie_tx_dataout_1d[511:8*45] } ;
            6'd20   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*44], jPcie_tx_dataout_1d[511:8*44] } ;
            6'd21   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*43], jPcie_tx_dataout_1d[511:8*43] } ;
            6'd22   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*42], jPcie_tx_dataout_1d[511:8*42] } ;
            6'd23   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*41], jPcie_tx_dataout_1d[511:8*41] } ;
            6'd24   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*40], jPcie_tx_dataout_1d[511:8*40] } ;
            6'd25   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*39], jPcie_tx_dataout_1d[511:8*39] } ;
            6'd26   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*38], jPcie_tx_dataout_1d[511:8*38] } ;
            6'd27   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*37], jPcie_tx_dataout_1d[511:8*37] } ;
            6'd28   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*36], jPcie_tx_dataout_1d[511:8*36] } ;
            6'd29   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*35], jPcie_tx_dataout_1d[511:8*35] } ;
            6'd30   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*34], jPcie_tx_dataout_1d[511:8*34] } ;
            6'd31   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*33], jPcie_tx_dataout_1d[511:8*33] } ;
            6'd32   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*32], jPcie_tx_dataout_1d[511:8*32] } ;
            6'd33   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*31], jPcie_tx_dataout_1d[511:8*31] } ;
            6'd34   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*30], jPcie_tx_dataout_1d[511:8*30] } ;
            6'd35   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*29], jPcie_tx_dataout_1d[511:8*29] } ;
            6'd36   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*28], jPcie_tx_dataout_1d[511:8*28] } ;
            6'd37   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*27], jPcie_tx_dataout_1d[511:8*27] } ;
            6'd38   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*26], jPcie_tx_dataout_1d[511:8*26] } ;
            6'd39   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*25], jPcie_tx_dataout_1d[511:8*25] } ;
            6'd40   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*24], jPcie_tx_dataout_1d[511:8*24] } ;
            6'd41   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*23], jPcie_tx_dataout_1d[511:8*23] } ;
            6'd42   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*22], jPcie_tx_dataout_1d[511:8*22] } ;
            6'd43   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*21], jPcie_tx_dataout_1d[511:8*21] } ;
            6'd44   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*20], jPcie_tx_dataout_1d[511:8*20] } ;
            6'd45   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*19], jPcie_tx_dataout_1d[511:8*19] } ;
            6'd46   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*18], jPcie_tx_dataout_1d[511:8*18] } ;
            6'd47   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*17], jPcie_tx_dataout_1d[511:8*17] } ;
            6'd48   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*16], jPcie_tx_dataout_1d[511:8*16] } ;
            6'd49   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*15], jPcie_tx_dataout_1d[511:8*15] } ;
            6'd50   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*14], jPcie_tx_dataout_1d[511:8*14] } ;
            6'd51   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*13], jPcie_tx_dataout_1d[511:8*13] } ;
            6'd52   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*12], jPcie_tx_dataout_1d[511:8*12] } ;
            6'd53   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*11], jPcie_tx_dataout_1d[511:8*11] } ;
            6'd54   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*10], jPcie_tx_dataout_1d[511:8*10] } ;
            6'd55   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*9],  jPcie_tx_dataout_1d[511:8*9]  } ;
            6'd56   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*8],  jPcie_tx_dataout_1d[511:8*8]  } ;
            6'd57   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*7],  jPcie_tx_dataout_1d[511:8*7]  } ;
            6'd58   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*6],  jPcie_tx_dataout_1d[511:8*6]  } ;
            6'd59   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*5],  jPcie_tx_dataout_1d[511:8*5]  } ;
            6'd60   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*4],  jPcie_tx_dataout_1d[511:8*4]  } ;
            6'd61   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*3],  jPcie_tx_dataout_1d[511:8*3]  } ;
            6'd62   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*2],  jPcie_tx_dataout_1d[511:8*2]  } ;
            default :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*1],  jPcie_tx_dataout_1d[511:8*1]  } ;
            endcase
        end
    end
else if(DWIDTH==256)
begin
    always @ ( posedge user_clk )
    begin
        if(req_op_sop_2d)
        begin
            case ( req_offset_2d[1:0] )
            2'd0    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*32] } ;
            2'd1    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*31], jPcie_tx_dataout_1d[255:8*31] } ;
            2'd2    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*30], jPcie_tx_dataout_1d[255:8*30] } ;
            default :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*29], jPcie_tx_dataout_1d[255:8*29] } ;
            endcase
        end
        else
        begin
            case ( req_offset_2d )       //实际物理地址的偏移
            5'd0    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*32] } ;
            5'd1    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*31], jPcie_tx_dataout_1d[255:8*31] } ;
            5'd2    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*30], jPcie_tx_dataout_1d[255:8*30] } ;
            5'd3    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*29], jPcie_tx_dataout_1d[255:8*29] } ;
            5'd4    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*28], jPcie_tx_dataout_1d[255:8*28] } ;
            5'd5    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*27], jPcie_tx_dataout_1d[255:8*27] } ;
            5'd6    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*26], jPcie_tx_dataout_1d[255:8*26] } ;
            5'd7    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*25], jPcie_tx_dataout_1d[255:8*25] } ;
            5'd8    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*24], jPcie_tx_dataout_1d[255:8*24] } ;
            5'd9    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*23], jPcie_tx_dataout_1d[255:8*23] } ;
            5'd10   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*22], jPcie_tx_dataout_1d[255:8*22] } ;
            5'd11   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*21], jPcie_tx_dataout_1d[255:8*21] } ;
            5'd12   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*20], jPcie_tx_dataout_1d[255:8*20] } ;
            5'd13   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*19], jPcie_tx_dataout_1d[255:8*19] } ;
            5'd14   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*18], jPcie_tx_dataout_1d[255:8*18] } ;
            5'd15   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*17], jPcie_tx_dataout_1d[255:8*17] } ;
            5'd16   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*16], jPcie_tx_dataout_1d[255:8*16] } ;
            5'd17   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*15], jPcie_tx_dataout_1d[255:8*15] } ;
            5'd18   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*14], jPcie_tx_dataout_1d[255:8*14] } ;
            5'd19   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*13], jPcie_tx_dataout_1d[255:8*13] } ;
            5'd20   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*12], jPcie_tx_dataout_1d[255:8*12] } ;
            5'd21   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*11], jPcie_tx_dataout_1d[255:8*11] } ;
            5'd22   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*10], jPcie_tx_dataout_1d[255:8*10] } ;
            5'd23   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*9],  jPcie_tx_dataout_1d[255:8*9]  } ;
            5'd24   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*8],  jPcie_tx_dataout_1d[255:8*8]  } ;
            5'd25   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*7],  jPcie_tx_dataout_1d[255:8*7]  } ;
            5'd26   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*6],  jPcie_tx_dataout_1d[255:8*6]  } ;
            5'd27   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*5],  jPcie_tx_dataout_1d[255:8*5]  } ;
            5'd28   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*4],  jPcie_tx_dataout_1d[255:8*4]  } ;
            5'd29   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*3],  jPcie_tx_dataout_1d[255:8*3]  } ;
            5'd30   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*2],  jPcie_tx_dataout_1d[255:8*2]  } ;
            default :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*1],  jPcie_tx_dataout_1d[255:8*1]  } ;
            endcase
        end
    end
end
else if(DWIDTH==128)
begin
    always @ ( posedge user_clk )
    begin
        if(req_op_sop_2d)
        begin
            case ( req_offset_2d[1:0] )
            2'd0    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*16] } ;
            2'd1    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*15], jPcie_tx_dataout_1d[127:8*15] } ;
            2'd2    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*14], jPcie_tx_dataout_1d[127:8*14] } ;
            default :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*13], jPcie_tx_dataout_1d[127:8*13] } ;
            endcase
        end
        else
        begin
            case ( req_offset_2d )       //实际物理地址的偏移
            4'd0    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*16] } ;
            4'd1    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*15], jPcie_tx_dataout_1d[127:8*15] } ;
            4'd2    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*14], jPcie_tx_dataout_1d[127:8*14] } ;
            4'd3    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*13], jPcie_tx_dataout_1d[127:8*13] } ;
            4'd4    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*12], jPcie_tx_dataout_1d[127:8*12] } ;
            4'd5    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*11], jPcie_tx_dataout_1d[127:8*11] } ;
            4'd6    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*10], jPcie_tx_dataout_1d[127:8*10] } ;
            4'd7    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*9],  jPcie_tx_dataout_1d[127:8*9]  } ;
            4'd8    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*8],  jPcie_tx_dataout_1d[127:8*8]  } ;
            4'd9    :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*7],  jPcie_tx_dataout_1d[127:8*7]  } ;
            4'd10   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*6],  jPcie_tx_dataout_1d[127:8*6]  } ;
            4'd11   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*5],  jPcie_tx_dataout_1d[127:8*5]  } ;
            4'd12   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*4],  jPcie_tx_dataout_1d[127:8*4]  } ;
            4'd13   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*3],  jPcie_tx_dataout_1d[127:8*3]  } ;
            4'd14   :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*2],  jPcie_tx_dataout_1d[127:8*2]  } ;
            default :   jPcie_seg_datain <= #U_DLY { jPcie_tx_dataout[0+:8*1],  jPcie_tx_dataout_1d[127:8*1]  } ;
            endcase
        end
    end
end
endgenerate

//产生下级数据的写信号
always @ ( posedge user_clk )
begin
    if ( ~iPcie_OPEN )
        jPcie_seg_wrreq <= #U_DLY 1'b0;
    else
        jPcie_seg_wrreq <= #U_DLY jPcie_tx_rdreq_2d;
end

//产生切片头
always @ ( posedge user_clk )
begin
    if ( jPcie_tx_rdreq_eop_2d ) //写操作的切片头
        jPcie_seg_Hwrreq <= #U_DLY 1'b1;
    else
        jPcie_seg_Hwrreq <= #U_DLY 1'b0;
end

always @ ( posedge user_clk)
begin
    if ( jPcie_tx_rdreq_eop_2d & ~req_type_2d) //写操作的切片头
        jPcie_seg_headin <= #U_DLY {req_op_sop_2d, req_op_eop_2d,
                                    2'b0,
                                    44'b0,
                                    REQ_TYPE_MWR,
                                    5'b0,rid_2d,
                                    req_curr_len_2d,
                                    seg_start_addr_2d};
    else if ( jPcie_tx_rdreq_eop_2d) //写操作的切片头
        jPcie_seg_headin <= #U_DLY {req_op_sop_2d, req_op_eop_2d,
                                    2'b0,
                                    req_info_2d[43:0],
                                    REQ_TYPE_MRD,
                                    5'b0,rid_2d,
                                    req_curr_len_2d,
                                    seg_start_addr_2d};
    else
        ;
end

assign oPcie_seg_headin = jPcie_seg_headin;
assign oPcie_seg_Hwrreq = jPcie_seg_Hwrreq;
assign oPcie_seg_datain = jPcie_seg_datain;
assign oPcie_seg_wrreq  = jPcie_seg_wrreq ;

//===========================================================================
//  打拍延迟
//===========================================================================
//delay
always @ ( posedge user_clk )
begin
    req_op_sop_1d <= #U_DLY req_op_sop;
    req_op_sop_2d <= #U_DLY req_op_sop_1d;
end
always @ ( posedge user_clk )
begin
    req_op_eop_1d <= #U_DLY req_op_eop;
    req_op_eop_2d <= #U_DLY req_op_eop_1d;
end

//delay address
always @ ( posedge user_clk )
begin
    if ( jPcie_tx_rdreq_eop )
        seg_start_addr_1d <= #U_DLY seg_start_addr;
    else
        ;
end
always @ ( posedge user_clk )
    seg_start_addr_2d <= #U_DLY seg_start_addr_1d;

//delay
always @ ( posedge user_clk )
begin
    if ( jPcie_tx_rdreq_eop )
        req_curr_len_1d <= #U_DLY req_curr_len;
    else
        ;
end
always @ ( posedge user_clk )
    req_curr_len_2d <= #U_DLY req_curr_len_1d;

//always@(posedge user_clk)
//begin
//    if(jPcie_tx_rdreq_eop)
//        seq_id_1d <= #U_DLY seq_id;
//    else
//        ;
//end
//always@(posedge user_clk)
//    seq_id_2d <= #U_DLY seq_id_1d;

//数据delay 用于移位操作
always @ ( posedge user_clk )
begin
    if ( jPcie_tx_rdreq_2d )
        jPcie_tx_dataout_1d <= #U_DLY jPcie_tx_dataout;
    else
        ;
end

always @ ( posedge user_clk )
begin
    if( req_op_sop )
        req_offset_1d <= #U_DLY req_offset;
    else
        ;
end
always @ ( posedge user_clk )
    req_offset_2d <= #U_DLY req_offset_1d;


always @ ( posedge user_clk )
begin
    if(jPcie_tx_rdreq_eop)
        req_type_1d <= #U_DLY req_type;
    else
        ;
end
always @ ( posedge user_clk )
    req_type_2d <= req_type_1d;

always @ ( posedge user_clk )
begin
    if(jPcie_tx_rdreq_eop)
        req_info_1d <= #U_DLY req_info;
    else
        ;
end
always @ ( posedge user_clk )
    req_info_2d <= req_info_1d;


always @ ( posedge user_clk )
begin
    jPcie_tx_rdreq_eop_1d <= #U_DLY jPcie_tx_rdreq_eop;
    jPcie_tx_rdreq_eop_2d <= #U_DLY jPcie_tx_rdreq_eop_1d;
end


//打拍延时
always@(posedge user_clk )
begin
    jPcie_tx_rdreq_1d <= #U_DLY jPcie_tx_rdreq;
    jPcie_tx_rdreq_2d <= #U_DLY jPcie_tx_rdreq_1d;
end

always @ ( posedge user_clk )
begin
    if ( jPcie_tx_rdreq_eop )
        rid_1d <= #U_DLY rid;
    else
        ;
end

always @ ( posedge user_clk )
    rid_2d <= #U_DLY rid_1d;

endmodule
