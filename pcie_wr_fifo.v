
`timescale 100ps / 1ps
module pcie_wr_fifo #(
parameter   BUFUNIT = 4096,     //4096 or 256
parameter   DWIDTH  = 256       //256
)(
// ===========================================================================
//part0: port singal define
// ===========================================================================
input                   user_clk        ,
input                   user_rst        ,

//fifo write side
output  reg             oPcie_ready     ,       //按256byte为分片形式送出
input       [143:0]     iPcie_headin    ,
input                   iPcie_Hwrreq    ,
input       [DWIDTH-1:0]iPcie_datain    ,
input                   iPcie_wrreq     ,
//fifo read side
output  reg             oPcie_empty     ,       //按256byte为分片形式送出
output      [143:0]     oPcie_headout   ,
input                   iPcie_Hrdreq    ,
output      [DWIDTH-1:0]oPcie_dataout   ,
input                   iPcie_rdreq
);

localparam  U_DLY             = 1 ;

localparam  HEAD_DEPTHBIT = (BUFUNIT==4096)? 3 : 5;
localparam  DATA_DEPTHBIT = clogb2(BUFUNIT) - clogb2(DWIDTH/8);

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


reg     [HEAD_DEPTHBIT+DATA_DEPTHBIT:0]     jdata_wradrs    ;
wire    [HEAD_DEPTHBIT+DATA_DEPTHBIT:0]     jdata_rdadrs    ;
reg     [DATA_DEPTHBIT-1: 0]                jdata_rdadrs_   ;
wire    [HEAD_DEPTHBIT: 0]                  jhead_wradrs    ;
reg     [HEAD_DEPTHBIT: 0]                  jhead_wradrs_1d ;
wire    [HEAD_DEPTHBIT: 0]                  jhead_rdadrs    ;
reg     [HEAD_DEPTHBIT: 0]                  ram_rptr0       ;
reg     [HEAD_DEPTHBIT: 0]                  ram_rptr0_1d    ;
reg     [HEAD_DEPTHBIT: 0]                  ram_rptr1       ;
wire    [HEAD_DEPTHBIT: 0]                  head_wrusedw    ;
wire    [HEAD_DEPTHBIT: 0]                  head_rdusedw    ;

generate if(BUFUNIT==4096)
begin
    always @ ( posedge user_clk )
    begin
        if(user_rst)
            oPcie_ready <= #U_DLY 1'b1;
        else if( iPcie_Hwrreq )
            oPcie_ready <= #U_DLY ( head_wrusedw >= {1'b0,{(HEAD_DEPTHBIT-2){1'b1}},2'b01} )? 1'b0 : 1'b1;
        else
            oPcie_ready <= #U_DLY ( head_wrusedw > {1'b0,{(HEAD_DEPTHBIT-2){1'b1}},2'b01} )? 1'b0 : 1'b1;
    end
end
else
begin
    always @ ( posedge user_clk )
    begin
        if(user_rst)
            oPcie_ready <= #U_DLY 1'b1;
        else if( iPcie_Hwrreq )
            oPcie_ready <= #U_DLY ( head_wrusedw >= {1'b0,{(HEAD_DEPTHBIT-2){1'b1}},2'b0} )? 1'b0 : 1'b1;
        else
            oPcie_ready <= #U_DLY ( head_wrusedw > {1'b0,{(HEAD_DEPTHBIT-2){1'b1}},2'b0} )? 1'b0 : 1'b1;
    end
end
endgenerate

always @ ( posedge user_clk )
begin
    if ( user_rst )
        oPcie_empty <= #U_DLY 1'b1;
    else if ( iPcie_Hrdreq )
        oPcie_empty <= #U_DLY (head_rdusedw == {{(HEAD_DEPTHBIT){1'b0}},1'b1})? 1'b1 : 1'b0;
    else
        oPcie_empty <= #U_DLY (head_rdusedw == {(HEAD_DEPTHBIT+1){1'b0}})? 1'b1 : 1'b0;
end

assign head_wrusedw = jhead_wradrs - ram_rptr0_1d ;
assign head_rdusedw = jhead_wradrs_1d - ram_rptr0 ;

//缓存数据包或者写操作指令，最大支持4Kbyte
sdp_ram #(
    .DATA_WIDTH     ( 144           ),
    .ADDR_WIDTH     ( HEAD_DEPTHBIT ),
    .READ_LATENCY   ( 1             ),
    .MEMORY_TYPE    ( "distributed" )
)
u_head_data(
    .clka           ( user_clk      ),
    .addra          ( jhead_wradrs[HEAD_DEPTHBIT-1:0]),
    .dina           ( iPcie_headin  ),
    .wea            ( iPcie_Hwrreq  ),
    .clkb           ( user_clk      ),
    .addrb          ( jhead_rdadrs[HEAD_DEPTHBIT-1:0]),
    .doutb          ( oPcie_headout )
);


sdp_ram #(
    .DATA_WIDTH     ( DWIDTH    ),
    .ADDR_WIDTH     ( HEAD_DEPTHBIT+DATA_DEPTHBIT),
    .READ_LATENCY   ( 2         ),
    .MEMORY_TYPE    ( "block"   )
)
u_data_data(
    .clka           ( user_clk      ),
    .addra          ( jdata_wradrs[HEAD_DEPTHBIT+DATA_DEPTHBIT-1:0]),
    .dina           ( iPcie_datain  ),
    .wea            ( iPcie_wrreq   ),
    .clkb           ( user_clk      ),
    .addrb          ( jdata_rdadrs[HEAD_DEPTHBIT+DATA_DEPTHBIT-1:0]),
    .doutb          ( oPcie_dataout )
);

//总共缓存16个包，分bank缓存
//write side
always @ ( posedge user_clk )
begin
    if ( user_rst )
        jdata_wradrs <= #U_DLY {(HEAD_DEPTHBIT+DATA_DEPTHBIT+1){1'b0}};
    else if ( iPcie_Hwrreq )     //写完一个包，切换bank
    begin
        jdata_wradrs[HEAD_DEPTHBIT+DATA_DEPTHBIT:DATA_DEPTHBIT]  <= #U_DLY jdata_wradrs[HEAD_DEPTHBIT+DATA_DEPTHBIT:DATA_DEPTHBIT] + 1'b1;
        jdata_wradrs[DATA_DEPTHBIT-1:0]  <= #U_DLY {DATA_DEPTHBIT{1'b0}};
    end
    else if ( iPcie_wrreq )
    begin
        jdata_wradrs[HEAD_DEPTHBIT+DATA_DEPTHBIT:DATA_DEPTHBIT]  <= #U_DLY jdata_wradrs[HEAD_DEPTHBIT+DATA_DEPTHBIT:DATA_DEPTHBIT];
        jdata_wradrs[DATA_DEPTHBIT-1:0]  <= #U_DLY jdata_wradrs[DATA_DEPTHBIT-1:0] + 1'b1;
    end
    else
        ;
end
//read side
always @ ( posedge user_clk )
begin
    if ( user_rst )
        jdata_rdadrs_ <= #U_DLY {DATA_DEPTHBIT{1'b0}};
    else if ( iPcie_Hrdreq )     //读完一个包，切换bank
    begin
        jdata_rdadrs_ <= #U_DLY {DATA_DEPTHBIT{1'b0}};
    end
    else if ( iPcie_rdreq )
    begin
        jdata_rdadrs_ <= #U_DLY jdata_rdadrs_ + 1'b1;
    end
    else
        ;
end

assign jhead_wradrs = jdata_wradrs[HEAD_DEPTHBIT+DATA_DEPTHBIT:DATA_DEPTHBIT];

assign jdata_rdadrs = {ram_rptr0,jdata_rdadrs_};

always @ ( posedge user_clk )
    jhead_wradrs_1d <= #U_DLY jhead_wradrs;

always @ ( posedge user_clk )
    ram_rptr0_1d <= #U_DLY ram_rptr0;


always @ ( posedge user_clk )
begin
    if ( user_rst )
    begin
        ram_rptr0 <= #U_DLY {(HEAD_DEPTHBIT+1){1'b0}};
        ram_rptr1 <= #U_DLY {{(HEAD_DEPTHBIT){1'b0}},1'b1};
    end
    else if ( iPcie_Hrdreq )
    begin
        ram_rptr0 <= #U_DLY ram_rptr1;
        ram_rptr1 <= #U_DLY ram_rptr1 + 1'b1;
    end
end

assign jhead_rdadrs = iPcie_Hrdreq? ram_rptr1 : ram_rptr0;




endmodule