
`timescale 100ps / 1ps
module muti_func_fifo #(
parameter   LONGBUF = 0,
parameter   DWIDTH  = 512,      //256 or 128 or 64
parameter   HWIDTH  = 144       //288 or 144 or 72
)(
// ===========================================================================
//part0: port singal define
// ===========================================================================
input                       user_clk        ,
input                       user_rst        ,

//fifo write side
output                      oInfo_ready     ,       //Send in the form of 256 bytes
input       [HWIDTH-1:0]    iInfo_headin    ,
input                       iInfo_Hwrreq    ,
input       [DWIDTH-1:0]    iInfo_datain    ,
input                       iInfo_wrreq     ,
//fifo read side
output                      oInfo_empty     ,       //Send in the form of 256 bytes
output      [HWIDTH-1:0]    oInfo_headout   ,
input                       iInfo_Hrdreq    ,
output      [DWIDTH-1:0]    oInfo_dataout   ,
input                       iInfo_rdreq     ,
input                       iInfo_Hrdreq_ag ,        //Do not switch banks
output  reg [7:0]           ostate_dbg
);

localparam  U_DLY   = 1 ;

localparam  DATA_DEPTHBIT = (LONGBUF==1)? 12 : 9;       //4K or 512
localparam  HEAD_DEPTHBIT = (LONGBUF==1)? 8 : 6;        //256 or 64

//function integer clogb2;
//input [31:0] depthbit;
//integer i;
//begin
//    clogb2 = 1;
//    for (i = 0; 2**i < depthbit; i = i + 1)
//    begin
//        clogb2 = i + 1;
//    end
//end
//endfunction


reg                             sop_flg         ;
wire    [HWIDTH+15:0]           jhead_din       ;
wire    [HWIDTH+15:0]           jhead_dout      ;
wire                            jhead_empty     ;
wire                            jhead_full      ;
wire    [HEAD_DEPTHBIT:0]       jhead_usedw     ;
reg                             jhead_ready     ;

reg                             jdata_empty     ;
reg                             jdata_ready     ;

reg     [DATA_DEPTHBIT-1:0]     jdata_wradrs    ;
reg     [DATA_DEPTHBIT-1:0]     jdata_rdadrs_   ;
wire    [DATA_DEPTHBIT-1:0]     jdata_rdadrs    ;
wire    [DATA_DEPTHBIT-1:0]     jdata_wr_usedw  ;
wire    [DATA_DEPTHBIT-1:0]     jdata_rd_usedw  ;

reg     [DATA_DEPTHBIT-1:0]     jdata_sop_wradrs_;
wire    [DATA_DEPTHBIT-1:0]     jdata_sop_wradrs;

reg                             load_rdadrs     ;
wire    [DATA_DEPTHBIT-1:0]     jdata_sop_rdadrs;

reg                             head_overflow   ;
reg                             abnormal_state  ;
reg     [ 7: 0]                 abnormal_state_dly;
reg     [ 3: 0]                 self_rst_ing    ;
reg                             self_rst        ;
reg     [ 2: 0]                 self_rst_cnt    ;

always @ ( posedge user_clk )
    jdata_ready <= #U_DLY ( jdata_wr_usedw[DATA_DEPTHBIT-1:6] == {(DATA_DEPTHBIT-6){1'b1}} )? 1'b0 : 1'b1;

always @ ( posedge user_clk )
begin
    if( user_rst | self_rst )
        jdata_empty <= #U_DLY 1'b1;
    else if( iInfo_rdreq )
        jdata_empty <= #U_DLY (jdata_rd_usedw == {{(DATA_DEPTHBIT-1){1'b0}},1'b1})? 1'b1 : 1'b0;
    else
        jdata_empty <= #U_DLY (jdata_rd_usedw == {DATA_DEPTHBIT{1'b0}})? 1'b1 : 1'b0;
end
assign oInfo_empty = jhead_empty;   //jdata_empty | jhead_empty;
assign oInfo_ready = jdata_ready & jhead_ready;

assign jdata_rd_usedw = jdata_wradrs - jdata_rdadrs ;
assign jdata_wr_usedw = jhead_empty? jdata_wradrs - jdata_sop_wradrs : jdata_wradrs - jdata_sop_rdadrs;

always @ ( posedge user_clk )
begin
    if( sop_flg & iInfo_wrreq )
        jdata_sop_wradrs_ <= jdata_wradrs;
    else
        ;
end
assign jdata_sop_wradrs = sop_flg? jdata_wradrs : jdata_sop_wradrs_;
always @ ( posedge user_clk )
begin
    if( user_rst | self_rst )
        sop_flg <= 1'b1;
    else if( iInfo_Hwrreq )
        sop_flg <= 1'b1;
    else if( iInfo_wrreq )
        sop_flg <= 1'b0;
    else
        ;
end

//Cache packets or write instructions, with a maximum of 2kbyte supported
assign jhead_din = {{(16-DATA_DEPTHBIT){1'b0}},jdata_sop_wradrs,iInfo_headin};
always @ ( posedge user_clk )
    jhead_ready <= ( jhead_usedw[HEAD_DEPTHBIT:3]>={1'b0,{(HEAD_DEPTHBIT-3){1'b1}}} )? 1'b0 : 1'b1;

always@(posedge user_clk)
begin
    if(user_rst | self_rst)
        head_overflow <= 1'b0;
    else if(jhead_full & iInfo_Hwrreq)
        head_overflow <= 1'b1;
    else
        ;
end

sync_fifo #(
    .DATA_WIDTH     ( HWIDTH+16     ),
    .DEPTH_WIDTH    ( HEAD_DEPTHBIT ),
    .MEMORY_TYPE    ( "distributed" )
)
u_head_fifo(
    .clk            ( user_clk      ),
    .srst           ( user_rst | self_rst),
    .din            ( jhead_din     ),
    .wr_en          ( iInfo_Hwrreq  ),
    .rd_en          ( iInfo_Hrdreq  ),
    .dout           ( jhead_dout    ),
    .full           ( jhead_full    ),
    .empty          ( jhead_empty   ),
    .alempty        ( ),
    .wr_data_count  ( jhead_usedw   ),
    .wr_rst_busy    ( ),
    .rd_rst_busy    ( )
);

assign oInfo_headout = jhead_dout[HWIDTH-1:0];
assign jdata_sop_rdadrs = jhead_dout[HWIDTH+DATA_DEPTHBIT-1:HWIDTH];

generate if(LONGBUF==0)
begin
    sdp_ram #(
        .DATA_WIDTH     ( DWIDTH        ),
        .ADDR_WIDTH     ( DATA_DEPTHBIT ),
        .READ_LATENCY   ( 2             ),
        .MEMORY_TYPE    ( "block"       )
    )
    u_data_data(
        .clka           ( user_clk      ),
        .addra          ( jdata_wradrs  ),
        .dina           ( iInfo_datain  ),
        .wea            ( iInfo_wrreq   ),
        .clkb           ( user_clk      ),
        .addrb          ( jdata_rdadrs  ),
        .doutb          ( oInfo_dataout )
    );
end
else
begin
    sdp_ram #(
        .DATA_WIDTH     ( DWIDTH        ),
        .ADDR_WIDTH     ( DATA_DEPTHBIT ),
        .READ_LATENCY   ( 2             ),
        .MEMORY_TYPE    ( "ultra"       )
    )
    u_data_data(
        .clka           ( user_clk      ),
        .addra          ( jdata_wradrs  ),
        .dina           ( iInfo_datain  ),
        .wea            ( iInfo_wrreq   ),
        .clkb           ( user_clk      ),
        .addrb          ( jdata_rdadrs  ),
        .doutb          ( oInfo_dataout )
    );
end
endgenerate


//write side
always @ ( posedge user_clk )
begin
    if( user_rst | self_rst )
        jdata_wradrs <= #U_DLY {DATA_DEPTHBIT{1'b0}};
    else if( iInfo_wrreq )
        jdata_wradrs <= #U_DLY jdata_wradrs + 1'b1;
    else
        ;
end
//read side
always @ ( posedge user_clk )
begin
    if( user_rst | self_rst )
        jdata_rdadrs_ <= #U_DLY {DATA_DEPTHBIT{1'b0}};
    else if( iInfo_rdreq )
        jdata_rdadrs_ <= #U_DLY jdata_rdadrs + 1'b1;
    else
        ;
end
always @ ( posedge user_clk )
begin
    if( user_rst | self_rst )
        load_rdadrs <= #U_DLY 1'b1;
    else if( iInfo_Hrdreq_ag | iInfo_Hrdreq )
        load_rdadrs <= #U_DLY 1'b1;
    else if( iInfo_rdreq )
        load_rdadrs <= #U_DLY 1'b0;
    else
        ;
end




assign jdata_rdadrs = ( load_rdadrs & ~jhead_empty )? jdata_sop_rdadrs : jdata_rdadrs_;

//============================
//  abnormal detect
//============================
always @ ( posedge user_clk )
    abnormal_state <= ( ~oInfo_ready & oInfo_empty )? 1'b1 : 1'b0;

always @ ( posedge user_clk )
begin
    if( abnormal_state )
        abnormal_state_dly <= abnormal_state_dly + 1'b1;
    else
        abnormal_state_dly <= 8'b0;
end

always @ ( posedge user_clk )
begin
    if( user_rst )
        self_rst_ing <= 4'b0;
    else if( abnormal_state_dly[7] | (self_rst_ing!=4'b0) )
        self_rst_ing <= self_rst_ing + 1'b1;
    else
        self_rst_ing <= 4'b0;
end

always @ ( posedge user_clk )
    self_rst <= ( self_rst_ing!=4'b0 )? 1'b1 : 1'b0;

always @ ( posedge user_clk )
begin
    if( user_rst )
        self_rst_cnt <= 3'b0;
    else if( self_rst & self_rst_ing==4'b0 )
        self_rst_cnt <= self_rst_cnt + 1'b1;
    else
        ;
end

always @ ( posedge user_clk )
    ostate_dbg <= {self_rst_cnt[2:0],head_overflow,
                   jhead_ready,jdata_ready,jhead_empty,jdata_empty};

endmodule


