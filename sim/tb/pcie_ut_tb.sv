
`resetall
`timescale 1ns/1ps

`include "parameter.sv"
`include "pcie_ut_tlps.sv"
`include "pcie_ut_intf.sv"
`include "pcie_app_tlps.sv"
`include "pcie_app_intf.sv"
`include "pcie_agent.sv"

module pcie_ut_tb;

reg     user_clk        ;
reg     user_rst        ;
reg     pcie_clk        ;
reg     pcie_rst        ;
reg     ddr4_clk        ;
reg     ddr4_rst        ;

pcie_axi_if u_pcie_axi_if();
assign u_pcie_axi_if.pcie_clk = pcie_clk;
pcie_app_if u_pcie_app_if();
assign u_pcie_app_if.app_clk = user_clk;



wire    [15: 0]         rq_oper_data_ex     ;
wire    [DWIDTH-1:0]    rq_oper_data        ;
wire                    rq_oper_wen         ;
wire                    rq_oper_ready       ;

wire    [15: 0]         rc_cplr_data_ex     ;
wire    [DWIDTH-1:0]    rc_cplr_data        ;   //Pcie write operation
wire                    rc_cplr_wen         ;
wire                    rc_cplr_ready       ;


/////////////////////////////////////////////////////////////////
//reg     [31:0]          tab_ready_random;
//always@(posedge u_top.clk_200m)
//    tab_ready_random <= $random;

pcie_user_if #(
    .DWIDTH     ( DWIDTH   )
)
u_pcie_user_if(
    .pcie_clk           ( pcie_clk  ),
    .pcie_rst           ( pcie_rst  ),
    .pcie_link_up       ( ~pcie_rst ),

    .s_axis_rq_tready   ( u_pcie_axi_if.s_axis_rq_tready),
    .s_axis_rq_tdata    ( u_pcie_axi_if.s_axis_rq_tdata ),
    .s_axis_rq_tkeep    ( u_pcie_axi_if.s_axis_rq_tkeep ),
    .s_axis_rq_tuser    ( u_pcie_axi_if.s_axis_rq_tuser ),
    .s_axis_rq_tlast    ( u_pcie_axi_if.s_axis_rq_tlast ),
    .s_axis_rq_tvalid   ( u_pcie_axi_if.s_axis_rq_tvalid),

    .m_axis_rc_tready   ( u_pcie_axi_if.m_axis_rc_tready),
    .m_axis_rc_tdata    ( u_pcie_axi_if.m_axis_rc_tdata ),
    .m_axis_rc_tkeep    ( u_pcie_axi_if.m_axis_rc_tkeep ),
    .m_axis_rc_tuser    ( u_pcie_axi_if.m_axis_rc_tuser ),
    .m_axis_rc_tlast    ( u_pcie_axi_if.m_axis_rc_tlast ),
    .m_axis_rc_tvalid   ( u_pcie_axi_if.m_axis_rc_tvalid),

    .m_axis_cq_tready   ( u_pcie_axi_if.m_axis_cq_tready),
    .m_axis_cq_tdata    ( u_pcie_axi_if.m_axis_cq_tdata ),
    .m_axis_cq_tkeep    ( u_pcie_axi_if.m_axis_cq_tkeep ),
    .m_axis_cq_tuser    ( u_pcie_axi_if.m_axis_cq_tuser ),
    .m_axis_cq_tlast    ( u_pcie_axi_if.m_axis_cq_tlast ),
    .m_axis_cq_tvalid   ( u_pcie_axi_if.m_axis_cq_tvalid),

    .s_axis_cc_tready   ( u_pcie_axi_if.s_axis_cc_tready),
    .s_axis_cc_tdata    ( u_pcie_axi_if.s_axis_cc_tdata ),
    .s_axis_cc_tkeep    ( u_pcie_axi_if.s_axis_cc_tkeep ),
    .s_axis_cc_tuser    ( u_pcie_axi_if.s_axis_cc_tuser ),
    .s_axis_cc_tlast    ( u_pcie_axi_if.s_axis_cc_tlast ),
    .s_axis_cc_tvalid   ( u_pcie_axi_if.s_axis_cc_tvalid),

    .rc_cplr_data_ex    ( rc_cplr_data_ex   ),
    .rc_cplr_data       ( rc_cplr_data      ),
    .rc_cplr_wen        ( rc_cplr_wen       ),
    .rc_cplr_ready      ( rc_cplr_ready     ),

    .cq_oper_data_ex    (           ),
    .cq_oper_data       (           ),
    .cq_oper_wen        (           ),
    .cq_oper_ready      ( 1'b1      ),

    .rq_user_clk        ( user_clk          ),
    .rq_user_rst        ( user_rst          ),
    .rq_oper_data_ex    ( rq_oper_data_ex   ),
    .rq_oper_data       ( rq_oper_data      ),
    .rq_oper_wen        ( rq_oper_wen       ),
    .rq_oper_ready      ( rq_oper_ready     ),

    .cc_user_clk        ( 1'b0          ),
    .cc_user_rst        ( 1'b0          ),
    .cc_cplr_data_ex    ( 16'b0         ),
    .cc_cplr_data       ( 128'b0        ),
    .cc_cplr_wen        ( 1'b0          ),
    .cc_cplr_ready      (               ),

    .odbg_inc           ( ),
    .odbg_info          ( )
);
pcie_user_top #(
    .MAXPAYLOAD     ( 256       ),
    .MAXREADREQ     ( 512       ),
    .MAXTAG         ( MAXTAG    ),            //32 or 64
    .DWIDTH         ( DWIDTH    )
)
u_pcie_user_top(
    .pcie_clk               ( pcie_clk  ),
    .pcie_rst               ( pcie_rst  ),
    .pcie_link_up           ( ~pcie_rst ),

    .user_clk               ( user_clk  ),
    .user_rst               ( user_rst  ),

    .iPcie_OPEN             ( 1'b1      ),
    .iTAG_recovery          ( 1'b1      ),
    .iTAG_tout_set          ( 16'h0002  ),

    .cpl_tag_end_dbg        ( ),
    .pcie_dbg               ( ),
    .tag_timeout_flg_dbg    ( ),
    .cpl_dw_err_flg_dbg     ( ),
//    .cpl_err_code_dbg       ( ),

    .rq_oper_data_ex        ( rq_oper_data_ex   ),
    .rq_oper_data           ( rq_oper_data      ),
    .rq_oper_wen            ( rq_oper_wen       ),
    .rq_oper_ready          ( rq_oper_ready     ),

    .rc_cplr_data_ex        ( rc_cplr_data_ex   ),
    .rc_cplr_data           ( rc_cplr_data      ),   //Pcie write operation
    .rc_cplr_wen            ( rc_cplr_wen       ),
    .rc_cplr_ready          ( rc_cplr_ready     ),

    .oPcie_tx_ready         ( u_pcie_app_if.pcie_tx_ready   ),       //按256byte为分片形式送出
    .iPcie_tx_headin        ( u_pcie_app_if.pcie_tx_headin  ),
    .iPcie_tx_Hwrreq        ( u_pcie_app_if.pcie_tx_Hwrreq  ),
    .iPcie_tx_datain        ( u_pcie_app_if.pcie_tx_datain  ),
    .iPcie_tx_wrreq         ( u_pcie_app_if.pcie_tx_wrreq   ),

    .iPcie_rx_ready         ( u_pcie_app_if.pcie_rx_ready   ),
    .oPcie_rx_headin        ( u_pcie_app_if.pcie_rx_headin  ),
    .oPcie_rx_Hwrreq        ( u_pcie_app_if.pcie_rx_Hwrreq  ),
    .oPcie_rx_datain        ( u_pcie_app_if.pcie_rx_datain  ),
    .oPcie_rx_wrreq         ( u_pcie_app_if.pcie_rx_wrreq   )
);







pcie_agent u_pcie_agent;
pcie_axi_agent u_pcie_axi_agent;
pcie_app_agent u_pcie_app_agent;

initial
begin
//  u_pcie_axi_agent = new(u_pcie_axi_if,rqtlps,rctlps,cqtlps,cctlps);
//  u_pcie_agent = new(rqtlps,rctlps,cqtlps,cctlps);
    u_pcie_axi_agent = new(u_pcie_axi_if);
    u_pcie_app_agent = new(u_pcie_app_if);
    u_pcie_agent = new();

    u_pcie_agent.rqtlps_rx = u_pcie_axi_agent.rqtlps_tx;
    u_pcie_axi_agent.rctlps_rx = u_pcie_agent.rctlps_tx;
    u_pcie_axi_agent.cqtlps_rx = u_pcie_agent.cqtlps_tx;
    u_pcie_agent.cctlps_rx = u_pcie_axi_agent.cctlps_tx;

    u_pcie_agent.apptlps_rx = u_pcie_app_agent.apptlps_tx;
    u_pcie_app_agent.apptlps_rx = u_pcie_agent.apptlps_tx;
end


initial
begin
    u_pcie_axi_if.axi_init;
    u_pcie_app_if.app_init;

    wait(pcie_rst==1'b0);
    wait(user_rst==1'b0);
    #100ns;
    fork
//        u_pcie_agent.init_cfg;
        u_pcie_agent.run;
        u_pcie_axi_agent.run;
        u_pcie_app_agent.run;
        u_pcie_agent.pcie_wr_and_rd_adrs_add(200,64'h1234567800000000,1500,1800);
//      u_pcie_agent.pcie_wr_and_rd(1000,250,1111);
    join
end


always @ *
    user_clk <= #2.01ns ~ user_clk;
always @ *
    pcie_clk <= #2ns ~ pcie_clk;

initial
begin
    pcie_clk = 1'b0;
    pcie_rst = 1'b1;
    user_clk = 1'b0;
    user_rst = 1'b1;

    #1us;
    user_rst = 1'b0;
    pcie_rst = 1'b0;
end





endmodule


















