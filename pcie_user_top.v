
`timescale 100ps / 1ps
module pcie_user_top #(
    parameter   MAXPAYLOAD = 256,
    parameter   MAXREADREQ = 512,
    parameter   MAXTAG = 64,            //32 or 64
    parameter   DWIDTH = 256
)(
input                       pcie_clk                ,
input                       pcie_rst                ,
input                       pcie_link_up            ,
//clk domain of user side
input                       user_clk                ,
input                       user_rst                ,

input                       iPcie_OPEN              ,
input                       iTAG_recovery           ,
input       [15: 0]         iTAG_tout_set           ,
//input                       credit_en               ,
//status
//output      [MAXTAG-1:0]    res_tag_valid_dbg       ,
output      [MAXTAG-1:0]    cpl_tag_end_dbg         ,
output      [63: 0]         pcie_dbg                ,
output                      tag_timeout_flg_dbg     ,
output                      cpl_dw_err_flg_dbg      ,
//output      [ 5: 0]         cpl_err_code_dbg        ,
//output                      res_tag_empty           ,
//
output      [15: 0]         rq_oper_data_ex         ,
output      [DWIDTH-1:0]    rq_oper_data            ,
output                      rq_oper_wen             ,
input                       rq_oper_ready           ,

input       [15: 0]         rc_cplr_data_ex         ,
input       [DWIDTH-1:0]    rc_cplr_data            ,   //Pcie write operation
input                       rc_cplr_wen             ,
output                      rc_cplr_ready           ,

output                      oPcie_tx_ready          ,       //按256byte为分片形式送出
input       [143:0]         iPcie_tx_headin         ,
input                       iPcie_tx_Hwrreq         ,
input       [DWIDTH-1:0]    iPcie_tx_datain         ,
input                       iPcie_tx_wrreq          ,

input                       iPcie_rx_ready          ,
output      [143:0]         oPcie_rx_headin         ,
output                      oPcie_rx_Hwrreq         ,
output      [DWIDTH-1:0]    oPcie_rx_datain         ,
output                      oPcie_rx_wrreq
);


localparam  U_DLY       = 1     ;


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

(* ASYNC_REG = "TRUE" *)reg         pcie_link_meta      ;
(* ASYNC_REG = "TRUE" *)reg         pcie_link_syn       ;
(* ASYNC_REG = "TRUE" *)reg         jPcie_OPEN_meta     ;
(* ASYNC_REG = "TRUE" *)reg         jPcie_OPEN_syn      ;
(* ASYNC_REG = "TRUE" *)reg         jTAG_recovery_meta  ;
(* ASYNC_REG = "TRUE" *)reg         jTAG_recovery_syn   ;
(* ASYNC_REG = "TRUE" *)reg [15: 0] jTAG_tout_set_meta  ;
(* ASYNC_REG = "TRUE" *)reg [15: 0] jTAG_tout_set_syn   ;

//wire    [23: 0]             rq_oper_wr_data_ex  ;
//wire    [DWIDTH-1:0]        rq_oper_wr_data     ;
//wire                        rq_oper_wr_wen      ;
//wire                        rq_oper_wr_ready    ;
//
//wire    [23: 0]             rq_oper_rd_data_ex  ;
//wire    [127:0]             rq_oper_rd_data     ;
//wire                        rq_oper_rd_wen      ;
//wire                        rq_oper_rd_ready    ;

//wire    [MAXTAG-1:0]        res_tag_timeout_flg ;
//wire    [MAXTAG-1:0]        res_tag_valid_flg   ;
wire    [MAXTAG-1:0]        cpl_tag_end_flg     ;
wire                        tag_tout_pulse      ;
//wire    [ 7: 0]             res_tag_rclm_din    ;
wire                        res_tag_rclm_wen    ;
wire    [ 5: 0]             used_tag_radrs      ;
wire    [143:0]             used_tag_dout       ;
wire                        res_tag_init_done   ;

wire                        tag_tout_flg        ;
wire    [ 7: 0]             cpl_tag             ;
wire                        tag_legal_flg       ;

//wire                        res_tag_full        ;
wire                        res_tag_empty       ;
wire                        res_tag_ren         ;
wire    [ 7: 0]             res_tag_dout        ;
wire    [143:0]             curr_tag_msg        ;
//wire                        curr_tag_msg_en     ;

wire    [ 7: 0]             retry_tag           ;
wire    [143:0]             retry_data          ;
wire                        retry_req           ;
wire                        retry_ack           ;

reg     [ 3: 0]             jPcie_OPEN_chain    ;
reg                         jPcie_OPEN_and      ;
reg                         jPcie_OPEN_and_r    ;


wire    [31: 0]             jdbg_tx_info        ;
wire    [15: 0]             jdbg_cplr_info      ;
wire    [ 7: 0]             jdbg_tag_info       ;

reg     [31: 0]             user_rst_dly_cnt    ;
reg                         user_inter_rst      ;

//assign res_tag_valid_dbg = res_tag_valid_flg[MAXTAG-1:0];
assign cpl_tag_end_dbg   = cpl_tag_end_flg[MAXTAG-1:0];


assign pcie_dbg = {8'b0,jdbg_tag_info[7:0],jdbg_cplr_info[15:0],
                   jdbg_tx_info[31:0]};

//reg     [MAXTAG-1:0]        res_tag_timeout_flg_1d;
//reg     [MAXTAG-1:0]        res_tag_timeout_flg_rise;
//always@(posedge user_clk)
//    res_tag_timeout_flg_1d <= res_tag_timeout_flg;
//always@(posedge user_clk)
//    res_tag_timeout_flg_rise <= res_tag_timeout_flg & ~res_tag_timeout_flg_1d;

//always@(posedge user_clk)
//    tag_timeout_flg_dbg <= |res_tag_timeout_flg_rise;
assign tag_timeout_flg_dbg = tag_tout_pulse;

always @ (posedge user_clk)
begin
    if( user_rst )
    begin
        pcie_link_meta <= #U_DLY 1'b0;
        pcie_link_syn  <= #U_DLY 1'b0;
    end
    else
    begin
        pcie_link_meta <= #U_DLY pcie_link_up;
        pcie_link_syn  <= #U_DLY pcie_link_meta;
    end
end

always @ (posedge user_clk)
begin
    if( pcie_link_syn )
`ifdef  SIM_ON
        user_rst_dly_cnt <= 32'h80000000;
`else
        user_rst_dly_cnt <= (user_rst_dly_cnt[31:28]>=4'h4)? 32'h80000000 : user_rst_dly_cnt + 1'b1;
`endif
    else
        user_rst_dly_cnt <= 32'b0;
end
always@(posedge user_clk)
begin
    if(user_rst_dly_cnt[31])
        user_inter_rst <= 1'b0;
    else
        user_inter_rst <= 1'b1;
end


always@(posedge user_clk)
begin
    jPcie_OPEN_meta    <= iPcie_OPEN;
    jPcie_OPEN_syn     <= jPcie_OPEN_meta;
    jTAG_recovery_meta <= iTAG_recovery;
    jTAG_recovery_syn  <= jTAG_recovery_meta;
    jTAG_tout_set_meta <= iTAG_tout_set;
    jTAG_tout_set_syn  <= jTAG_tout_set_meta;
end

//=====================================================================
//  load config
//=====================================================================



always @ ( posedge user_clk)
begin
    if( user_inter_rst )
        jPcie_OPEN_chain <= #U_DLY 4'b0;
    else
        jPcie_OPEN_chain <= #U_DLY {jPcie_OPEN_chain[2:0],jPcie_OPEN_syn};
end

always @ ( posedge user_clk ) begin
    jPcie_OPEN_and_r <= #U_DLY &jPcie_OPEN_chain;
    jPcie_OPEN_and   <= #U_DLY jPcie_OPEN_and_r;
end

////=================================================================
////  ADD Sequence
////=================================================================
//reg     [ 7: 0]         seq_id              ;
//reg     [151:0]         pcie_tx_wr_headin   ;
//reg                     pcie_tx_wr_Hwrreq   ;
//reg     [DWIDTH-1:0]    pcie_tx_wr_datain   ;
//reg                     pcie_tx_wr_wrreq    ;
//reg     [151:0]         pcie_tx_rd_headin   ;
//reg                     pcie_tx_rd_Hwrreq   ;




//always@(posedge user_clk)
//begin
//    if(user_inter_rst)
//        seq_id <= 8'b0;
//    else if(iPcie_tx_wr_Hwrreq & iPcie_tx_rd_Hwrreq)
//        seq_id <= seq_id + 8'd2;
//    else if(iPcie_tx_wr_Hwrreq | iPcie_tx_rd_Hwrreq)
//        seq_id <= seq_id + 8'd1;
//    else
//        ;
//end




//always@(posedge user_clk)
//begin
//    pcie_tx_wr_headin[143:0] <= iPcie_tx_wr_headin;
//    pcie_tx_wr_Hwrreq <= iPcie_tx_wr_Hwrreq;
//    pcie_tx_wr_datain <= iPcie_tx_wr_datain;
//    pcie_tx_wr_wrreq  <= iPcie_tx_wr_wrreq ;
////    if(iPcie_tx_wr_Hwrreq)
////        pcie_tx_wr_headin[151:144] <= seq_id;
////    else
////        ;
//end
//always@(posedge user_clk)
//begin
//    pcie_tx_rd_headin[143:0] <= iPcie_tx_rd_headin;
//    pcie_tx_rd_Hwrreq <= iPcie_tx_rd_Hwrreq;
////    if(iPcie_tx_rd_Hwrreq)
////        pcie_tx_rd_headin[151:144] <= (iPcie_tx_wr_Hwrreq)? seq_id + 1'b1 : seq_id;
////    else
////        ;
//end



pcie_user_tx #(
    .MAXPAYLOAD         ( MAXPAYLOAD ),
    .DWIDTH             ( DWIDTH     )
) u_pcie_user_tx(
    .user_clk           ( user_clk          ),
    .user_rst           ( user_inter_rst    ),

    .iPcie_OPEN         ( jPcie_OPEN_and    ),
    .odbg_info          ( jdbg_tx_info      ),

    .rq_oper_data_ex    ( rq_oper_data_ex   ),  //Pcie write operation
    .rq_oper_data       ( rq_oper_data      ),
    .rq_oper_wen        ( rq_oper_wen       ),
    .rq_oper_ready      ( rq_oper_ready     ),

    .res_tag_empty      ( res_tag_empty     ),
    .res_tag_ren        ( res_tag_ren       ),
    .res_tag_dout       ( res_tag_dout      ),
    .curr_tag_msg       ( curr_tag_msg      ),

    .retry_tag          ( retry_tag         ),
    .retry_data         ( retry_data        ),
    .retry_req          ( retry_req         ),
    .retry_ack          ( retry_ack         ),

    .oPcie_tx_ready     ( oPcie_tx_ready    ),
    .iPcie_tx_headin    ( iPcie_tx_headin   ),
    .iPcie_tx_Hwrreq    ( iPcie_tx_Hwrreq   ),
    .iPcie_tx_datain    ( iPcie_tx_datain   ),
    .iPcie_tx_wrreq     ( iPcie_tx_wrreq    )
);


pcie_cplr_asm #(
    .MAXTAG             ( MAXTAG     ),
    .MAXREADREQ         ( MAXREADREQ ),
    .DWIDTH             ( DWIDTH     )
)u_pcie_cplr_asm(
    .user_clk           ( user_clk          ),
    .user_rst           ( user_inter_rst    ),

    .odbg_info          ( jdbg_cplr_info    ),

    .pcie_clk           ( pcie_clk          ),
    .pcie_rst           ( pcie_rst          ),
    .rc_cplr_data_ex    ( rc_cplr_data_ex   ),
    .rc_cplr_data       ( rc_cplr_data      ),  //Pcie read completion
    .rc_cplr_wen        ( rc_cplr_wen       ),
    .rc_cplr_ready      ( rc_cplr_ready     ),

//    .res_tag_timeout_flg( res_tag_timeout_flg ),
//    .res_tag_valid_flg  ( res_tag_valid_flg   ),
    .cpl_tag_end_flg    ( cpl_tag_end_flg   ),
    .tag_tout_pulse     ( tag_tout_pulse    ),
    .cpl_dw_err         ( cpl_dw_err_flg_dbg),
//    .err_code           ( cpl_err_code_dbg    ),
//    .res_tag_rclm_din   ( res_tag_rclm_din    ),
    .res_tag_rclm_wen   ( res_tag_rclm_wen  ),

    .used_tag_radrs     ( used_tag_radrs    ),
    .used_tag_dout      ( used_tag_dout     ),
    .tag_tout_flg       ( tag_tout_flg      ),
    .res_tag_init_done  ( res_tag_init_done ),

    .retry_tag          ( retry_tag         ),
    .retry_data         ( retry_data        ),
    .retry_req          ( retry_req         ),
    .retry_ack          ( retry_ack         ),
    .cpl_tag            ( cpl_tag           ),
    .tag_legal_flg      ( tag_legal_flg     ),

    .iPcie_rx_ready     ( iPcie_rx_ready    ),
    .oPcie_rx_headin    ( oPcie_rx_headin   ),
    .oPcie_rx_Hwrreq    ( oPcie_rx_Hwrreq   ),
    .oPcie_rx_datain    ( oPcie_rx_datain   ),
    .oPcie_rx_wrreq     ( oPcie_rx_wrreq    )

);

pcie_user_tag #(
    .MAXTAG             ( MAXTAG )
)u_pcie_user_tag(
    .user_clk           ( user_clk          ),
    .user_rst           ( user_inter_rst    ),

    .iPcie_OPEN         ( jPcie_OPEN_and    ),
    .iTAG_recovery      ( jTAG_recovery_syn ),   //tag self recovery enable
    .iTAG_tout_set      ( jTAG_tout_set_syn ),
    .odbg_info          ( jdbg_tag_info     ),

//    .res_tag_timeout_flg( res_tag_timeout_flg ),
//    .res_tag_valid_flg  ( res_tag_valid_flg   ),
//    .cpl_tag_end_flg    ( cpl_tag_end_flg     ),

//    .res_tag_rclm_din   ( res_tag_rclm_din    ),
    .res_tag_rclm_wen   ( res_tag_rclm_wen  ),

//    .res_tag_full       ( res_tag_full      ),
    .res_tag_empty      ( res_tag_empty     ),
    .res_tag_ren        ( res_tag_ren       ),
    .res_tag_dout       ( res_tag_dout      ),

    .retry_tag          ( retry_tag         ),
    .retry_ack          ( retry_ack         ),
    .cpl_tag            ( cpl_tag           ),
    .tag_legal_flg      ( tag_legal_flg     ),

    .curr_tag_msg       ( curr_tag_msg      ),
//    .curr_tag_msg_en    ( curr_tag_msg_en   ),
    .res_tag_init_done  ( res_tag_init_done ),
    .used_tag_radrs     ( used_tag_radrs    ),
    .used_tag_dout      ( used_tag_dout     ),
    .tag_tout_flg       ( tag_tout_flg      )

);


endmodule
