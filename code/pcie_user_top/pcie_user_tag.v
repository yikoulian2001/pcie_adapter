
`timescale 100ps / 1ps
module pcie_user_tag #(
parameter   MAXTAG     =   64
)(
// ===========================================================================
//part0: port singal define
// ===========================================================================
input                   user_clk            ,
input                   user_rst            ,

input                   iPcie_OPEN          ,
input                   iTAG_recovery       ,   //tag self recovery enable
input   [15: 0]         iTAG_tout_set       ,
output  [ 7: 0]         odbg_info           ,

//output  [MAXTAG-1:0]    res_tag_timeout_flg ,
//output  [MAXTAG-1:0]    res_tag_valid_flg   ,
//input   [MAXTAG-1:0]    cpl_tag_end_flg     ,

input                   res_tag_rclm_wen    ,

//output  reg             res_tag_full        ,
output  reg             res_tag_empty       ,
input                   res_tag_ren         ,
output  [ 7: 0]         res_tag_dout        ,

input   [ 7: 0]         retry_tag           ,
input                   retry_ack           ,
input   [ 7: 0]         cpl_tag             ,
output  reg             tag_legal_flg       ,

input   [143:0]         curr_tag_msg        ,
//input                   curr_tag_msg_en     ,
output  reg             res_tag_init_done   ,
input   [ 5: 0]         used_tag_radrs      ,
output  [143:0]         used_tag_dout       ,
output                  tag_tout_flg

);

localparam  U_DLY = 1;
localparam  MAXTAG_BIT = clogb2(MAXTAG);

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

//tag资源池控制信号

reg     [MAXTAG_BIT:0]      res_tag_wadrs       ;
//wire    [ 7: 0]             res_tag_din         ;
wire                        res_tag_wen         ;
//reg                         res_tag_wen_1d      ;
reg     [MAXTAG_BIT:0]      res_tag_radrs       ;
//reg                         res_tag_full        ;

reg     [ 9: 0]             timeout_gap         ;
reg                         timeout_gap_pulse   ;
reg     [15: 0]             local_time          ;
//reg     [MAXTAG*7-1:0]      res_tag_timeout     ;
//tag初始化信号
reg     [MAXTAG_BIT:0]      res_tag_init_time   ;

reg                         res_tag_rclm_wen_1d ;

reg                         res_tag_full        ;
//tag对应数据信息ram的控制信号

reg     [MAXTAG_BIT-1:0]    used_tag_wadrs      ;
reg     [143:0]             used_tag_din        ;
reg                         used_tag_wen        ;

//reg     [MAXTAG-1:0]        res_tag_valid       ;

wire    [MAXTAG_BIT:0]      res_tag_left        ;
reg     [MAXTAG_BIT:0]      res_tag_used        ;
wire    [MAXTAG_BIT:0]      res_tag_gap         ;
wire    [MAXTAG_BIT-1:0]    cpl_tag_gap         ;


assign odbg_info = {1'b0,res_tag_used,res_tag_init_done};
//===============================================
//  Tag manage
//===============================================
////tag资源池
//generate if(MAXTAG==32)
//begin : gen_tag_res
//    DISBRAM_SDP_D1_8x32 u_tag(
//        .a          ( res_tag_wadrs[MAXTAG_BIT-1:0]),
//        .d          ( res_tag_din   ),
//        .dpra       ( res_tag_radrs[MAXTAG_BIT-1:0]),
//        .clk        ( user_clk      ),
//        .we         ( res_tag_wen   ),
//        .qdpo_clk   ( user_clk      ),
//        .qdpo       ( res_tag_dout  )
//    );
//end
//else if(MAXTAG==64)
//begin
//    DISBRAM_SDP_D1_8x64 u_tag(
//        .a          ( res_tag_wadrs[MAXTAG_BIT-1:0]),
//        .d          ( res_tag_din   ),
//        .dpra       ( res_tag_radrs[MAXTAG_BIT-1:0]),
//        .clk        ( user_clk      ),
//        .we         ( res_tag_wen   ),
//        .qdpo_clk   ( user_clk      ),
//        .qdpo       ( res_tag_dout  )
//    );
//end
//endgenerate

//tag legal judge
assign res_tag_gap = res_tag_radrs[MAXTAG_BIT:0] - res_tag_wadrs[MAXTAG_BIT:0];
assign cpl_tag_gap = cpl_tag[MAXTAG_BIT-1:0] - res_tag_wadrs[MAXTAG_BIT-1:0];

always@(posedge user_clk)
begin
    if( res_tag_used > {1'b0,cpl_tag_gap})
        tag_legal_flg <= 1'b1;
    else
        tag_legal_flg <= 1'b0;
end

always@(posedge user_clk)
    res_tag_used <= {~res_tag_gap[MAXTAG_BIT],res_tag_gap[MAXTAG_BIT-1:0]};

assign res_tag_left = res_tag_wadrs - res_tag_radrs;
always @ ( posedge user_clk )
begin
    if ( ~res_tag_init_done )
        res_tag_wadrs <= #U_DLY {1'b1,{(MAXTAG_BIT){1'b0}}};
    else if ( res_tag_wen & ~res_tag_full )     //回收tag，写地址+1，
        res_tag_wadrs <= #U_DLY res_tag_wadrs + 1'b1;
end

always @ ( posedge user_clk )
begin
    if ( ~res_tag_init_done )
        res_tag_radrs <= #U_DLY {(MAXTAG_BIT+1){1'b0}};
    else if ( res_tag_ren )    //取用tag，读地址+1
        res_tag_radrs <= #U_DLY res_tag_radrs + 1'b1;
end

//读写位置相等，资源池空
always @ ( posedge user_clk )
begin
//    if ( user_rst )
//        res_tag_empty <= #U_DLY 1'b1;
//    else if ( res_tag_init_done )
    if ( res_tag_init_done )
    begin
        if( res_tag_ren )
            res_tag_empty <= #U_DLY (res_tag_wadrs == res_tag_radrs + 1'b1)? 1'b1 : 1'b0;
        else
            res_tag_empty <= #U_DLY (res_tag_wadrs == res_tag_radrs)? 1'b1 : 1'b0;
    end
    else
        res_tag_empty <= #U_DLY 1'b1;
end
//写位置 - 读位置 超过了Tag总数，资源池满
always @ ( posedge user_clk )
begin
//    if ( user_rst )
//        res_tag_full <= 1'b1;
//    else if( res_tag_wen )
    if( res_tag_wen )
        res_tag_full <= #U_DLY (res_tag_left == MAXTAG - 1)? 1'b1 : 1'b0;
    else
        res_tag_full <= #U_DLY (res_tag_left == MAXTAG)? 1'b1 : 1'b0;
end

assign res_tag_dout[7:MAXTAG_BIT] = {(8-MAXTAG_BIT){1'b0}};
assign res_tag_dout[MAXTAG_BIT-1:0] = res_tag_radrs[MAXTAG_BIT-1:0];

always@(posedge user_clk)
begin
    if(~iPcie_OPEN)
        timeout_gap <= 10'b0;
    else
        timeout_gap <= timeout_gap + 1'b1;
end
always@(posedge user_clk)
    timeout_gap_pulse <= (timeout_gap=={10{1'b1}})? 1'b1 : 1'b0;

always@(posedge user_clk)
begin
    if(~iPcie_OPEN)
        local_time <= 16'b0;
    else if(timeout_gap_pulse & iTAG_recovery)
        local_time <= local_time + 1'b1;
    else
        ;
end

wire    [MAXTAG_BIT-1:0]    tag_tout_wadrs;
wire    [15:0]              tag_tout_din;
wire                        tag_tout_wen;
wire    [MAXTAG_BIT-1:0]    tag_tout_radrs;
wire    [15:0]              tag_tout_dout;

sdp_ram #(
    .DATA_WIDTH     ( 16            ),
    .ADDR_WIDTH     ( MAXTAG_BIT    ),
    .READ_LATENCY   ( 1             ),
    .MEMORY_TYPE    ( "distributed" )
)
tag_tout(
    .clka           ( user_clk      ),
    .addra          ( tag_tout_wadrs),
    .dina           ( tag_tout_din  ),
    .wea            ( tag_tout_wen  ),
    .clkb           ( user_clk      ),
    .addrb          ( tag_tout_radrs),
    .doutb          ( tag_tout_dout )
);
assign tag_tout_wadrs = (retry_ack)? retry_tag[0+:MAXTAG_BIT] : res_tag_radrs[0+:MAXTAG_BIT];
assign tag_tout_din   = local_time;
assign tag_tout_wen   = res_tag_ren | retry_ack;

assign tag_tout_radrs = used_tag_radrs[0+:MAXTAG_BIT];
//always@(posedge user_clk)
//    tag_tout_flg <= (iTAG_recovery & ~res_tag_full & (local_time - tag_tout_dout >= iTAG_tout_set))? 1'b1 : 1'b0;
assign tag_tout_flg = (iTAG_recovery & ~res_tag_full & (local_time - tag_tout_dout >= iTAG_tout_set))? 1'b1 : 1'b0;



//genvar  tag_i;
//generate
//    for ( tag_i = 0; tag_i < MAXTAG; tag_i = tag_i + 1)
//    begin : gen_tag_i
//
//
//    always @ ( posedge user_clk )
//    begin
//        if ( ~iPcie_OPEN )
//            res_tag_timeout[(tag_i+1)*7-1:tag_i*7] <= #U_DLY 7'b0;
////        else if ( cpl_tag_end_flg[tag_i] | ((res_tag_din==tag_i) & res_tag_wen) )   //tag 被回收/ tag 接收完全，清除tag超时计数
//        else if ( cpl_tag_end_flg[tag_i] )   //tag 被回收/ tag 接收完全，清除tag超时计数
//            res_tag_timeout[(tag_i+1)*7-1:tag_i*7] <= #U_DLY 7'b0;
//        else if ( ~res_tag_valid[tag_i] & iTAG_recovery )       //Tag被使用
//        begin
//            if(timeout_gap_pulse)
//                res_tag_timeout[(tag_i+1)*7-1:tag_i*7] <= #U_DLY res_tag_timeout[tag_i*7+6]? 7'h40 : (res_tag_timeout[(tag_i+1)*7-1:tag_i*7] + 1'b1);
//            else
//                ;
//        end
//        else
//            ;
//    end
//
//    assign res_tag_timeout_flg[tag_i] = res_tag_timeout[tag_i*7+6];   //将超时信息输出
//
//    //tag有效标记，如果未被使用即认为tag有效
//    always @ ( posedge user_clk )
//    begin
//        if ( ~res_tag_init_done )
//            res_tag_valid[tag_i] <= #U_DLY 1'b1;
//        else if ( res_tag_wen & ~res_tag_full & res_tag_wadrs[MAXTAG_BIT-1:0]==tag_i)   //当tag资源被写入到资源池时，当前tag可用
//            res_tag_valid[tag_i] <= #U_DLY 1'b1;
//        else if ( res_tag_ren & (res_tag_dout[MAXTAG_BIT-1:0]==tag_i))  //当tag被从资源池里读出时，当前tag已被使用
//            res_tag_valid[tag_i] <= #U_DLY 1'b0;
//        else
//            ;
//    end
//
//    end
//endgenerate

//assign res_tag_valid_flg = res_tag_valid;

/******************************
    Tag初始化
******************************/
//系统起来，先初始化Tag


always @ ( posedge user_clk )
begin
    if ( ~iPcie_OPEN )
        res_tag_init_time <= #U_DLY {(MAXTAG_BIT+1){1'b0}};
    else if(res_tag_init_time == {(MAXTAG_BIT+1){1'b1}})
        res_tag_init_time <= #U_DLY {(MAXTAG_BIT+1){1'b1}};
    else
        res_tag_init_time <= #U_DLY res_tag_init_time + 1'b1;
end

//初始化Tag完成后，产生init_done信号
always @ ( posedge user_clk )
begin
    if ( (res_tag_init_time == {(MAXTAG_BIT+1){1'b1}}))
        res_tag_init_done <= #U_DLY 1'b1;
    else
        res_tag_init_done <= #U_DLY 1'b0;
end



//always @ ( posedge user_clk )
//    res_tag_rclm_wen_1d <= #U_DLY res_tag_rclm_wen;



assign res_tag_wen = res_tag_rclm_wen;//res_tag_rclm_wen_1d ;

//always @ ( posedge user_clk )
//    res_tag_wen_1d <= #U_DLY res_tag_wen;
//=============================================
//  Tag 对应读操作的信息
//=============================================
//用于当前使用的Tag的数据信息
sdp_ram #(
    .DATA_WIDTH     ( 144           ),
    .ADDR_WIDTH     ( MAXTAG_BIT    ),
    .READ_LATENCY   ( 1             ),
    .MEMORY_TYPE    ( "block"       )
)
TAG_MSG(
    .clka           ( user_clk      ),
    .addra          ( used_tag_wadrs),
    .dina           ( used_tag_din  ),
    .wea            ( used_tag_wen  ),
    .clkb           ( user_clk      ),
    .addrb          ( used_tag_radrs[MAXTAG_BIT-1:0]),
    .doutb          ( used_tag_dout )
);






always @ ( posedge user_clk )
begin
//    if ( user_rst )
//        used_tag_wadrs <= #U_DLY {(MAXTAG_BIT){1'b0}};
//    else if ( res_tag_init_done & res_tag_ren )     //当取用Tag时，将Tag信息作为写地址
    if ( res_tag_init_done & res_tag_ren )
        used_tag_wadrs <= #U_DLY res_tag_dout[MAXTAG_BIT-1:0];
//    if( res_tag_init_done & curr_tag_msg_en )
//    begin
//        used_tag_wadrs[MAXTAG_BIT+1:2] <= res_tag_dout[MAXTAG_BIT-1:0];
//        used_tag_wadrs[1:0]            <= curr_tag_msg[37:36];
//    end
    else
        ;
end

always @ ( posedge user_clk )
begin
    if ( res_tag_init_done & res_tag_ren )     //当前使用的Tag的数据信息，写入到Tag缓存里
        used_tag_din <= #U_DLY curr_tag_msg ;
//    if(curr_tag_msg_en)
//        used_tag_din <= #U_DLY curr_tag_msg[35:0];
    else
        ;
end

always @ ( posedge user_clk )
begin
    if ( res_tag_init_done & res_tag_ren )
        used_tag_wen <= #U_DLY 1'b1;
    else
        used_tag_wen <= #U_DLY 1'b0;
end

endmodule