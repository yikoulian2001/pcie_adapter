
`timescale 100ps / 1ps
module pcie_user_if #(
    parameter   DWIDTH = 256
)(
input                           pcie_clk            ,
input                           pcie_rst            ,
input                           pcie_link_up        ,

output      [DWIDTH-1:0]        s_axis_rq_tdata     ,
output      [61: 0]             s_axis_rq_tuser     ,
output      [DWIDTH/32-1:0]     s_axis_rq_tkeep     ,
output                          s_axis_rq_tlast     ,
output                          s_axis_rq_tvalid    ,
input       [ 3: 0]             s_axis_rq_tready    ,

input       [DWIDTH-1:0]        m_axis_rc_tdata     ,
input       [74: 0]             m_axis_rc_tuser     ,
input       [DWIDTH/32-1:0]     m_axis_rc_tkeep     ,
input                           m_axis_rc_tlast     ,
input                           m_axis_rc_tvalid    ,
output                          m_axis_rc_tready    ,

input       [DWIDTH-1:0]        m_axis_cq_tdata     ,
input       [87: 0]             m_axis_cq_tuser     ,
input       [DWIDTH/32-1:0]     m_axis_cq_tkeep     ,
input                           m_axis_cq_tlast     ,
input                           m_axis_cq_tvalid    ,
output                          m_axis_cq_tready    ,

output      [DWIDTH-1:0]        s_axis_cc_tdata     ,
output      [32: 0]             s_axis_cc_tuser     ,
output      [DWIDTH/32-1:0]     s_axis_cc_tkeep     ,
output                          s_axis_cc_tlast     ,
output                          s_axis_cc_tvalid    ,
input       [ 3: 0]             s_axis_cc_tready    ,

output      [15: 0]             rc_cplr_data_ex     ,
output      [DWIDTH-1:0]        rc_cplr_data        ,
output                          rc_cplr_wen         ,
input                           rc_cplr_ready       ,

output      [15: 0]             cq_oper_data_ex     ,
output      [159:0]             cq_oper_data        ,
output                          cq_oper_wen         ,
input                           cq_oper_ready       ,

input                           rq_user_clk         ,
input                           rq_user_rst         ,
input       [15: 0]             rq_oper_data_ex     ,
input       [DWIDTH-1:0]        rq_oper_data        ,
input                           rq_oper_wen         ,
output                          rq_oper_ready       ,

input                           cc_user_clk         ,
input                           cc_user_rst         ,
input       [15: 0]             cc_cplr_data_ex     ,
input       [127:0]             cc_cplr_data        ,
input                           cc_cplr_wen         ,
output                          cc_cplr_ready       ,

//output                          read_req            ,
//output      [ 7: 0]             req_tag             ,
//output      [255:0]             cap_cq_data         ,
//output      [ 1: 0]             cap_cq_wen          ,
//output      [255:0]             cap_cc_data         ,
//output                          cap_cc_wen          ,
//output      [255:0]             cap_rq_data         ,
//output                          cap_rq_wen          ,
output  reg [ 9: 0]             odbg_inc            ,
output      [63: 0]             odbg_info
);

wire    [15: 0]         dbg_rq_info;
wire    [15: 0]         dbg_rc_info;
wire    [15: 0]         dbg_cq_info;
wire    [15: 0]         dbg_cc_info;

assign odbg_info = {dbg_cc_info,dbg_cq_info,dbg_rc_info,dbg_rq_info};
//always@(posedge rq_user_clk)    //clk_250m
//begin
//    odbg_inc[1] <= rq_oper_wen & rq_oper_data_ex[22];   //eop
//    odbg_inc[0] <= rq_oper_wen & rq_oper_data_ex[23];   //sop
//end
//always@(posedge pcie_clk)
//begin
//    odbg_inc[5] <= rc_cplr_wen[1] & rc_cplr_data_ex[22];//eop
//    odbg_inc[4] <= rc_cplr_wen[1] & rc_cplr_data_ex[23];//sop
//    odbg_inc[3] <= rc_cplr_wen[0] & rc_cplr_data_ex[22];//eop
//    odbg_inc[2] <= rc_cplr_wen[0] & rc_cplr_data_ex[23];//sop
//end
//always@(posedge pcie_clk)
//begin
//    odbg_inc[7] <= cq_oper_wen & cq_oper_data_ex[22];   //eop
//    odbg_inc[6] <= cq_oper_wen & cq_oper_data_ex[23];   //sop
//end
//always@(posedge cc_user_clk)    //clk_100m
//begin
//    odbg_inc[9] <= cc_cplr_wen & cc_cplr_data_ex[22];   //eop
//    odbg_inc[8] <= cc_cplr_wen & cc_cplr_data_ex[23];   //sop
//end

pcie_rq_intf    #(
    .DWIDTH             ( DWIDTH            )
) u_pcie_rq_intf(
    .pcie_clk           ( pcie_clk          ),
    .pcie_rst           ( pcie_rst          ),
    .pcie_link_up       ( pcie_link_up      ),

    .s_axis_rq_tlast    ( s_axis_rq_tlast   ),
    .s_axis_rq_tdata    ( s_axis_rq_tdata   ),
    .s_axis_rq_tuser    ( s_axis_rq_tuser   ),
    .s_axis_rq_tkeep    ( s_axis_rq_tkeep   ),
    .s_axis_rq_tready   ( s_axis_rq_tready[0]),
    .s_axis_rq_tvalid   ( s_axis_rq_tvalid  ),

    .user_clk           ( rq_user_clk       ),
    .user_rst           ( rq_user_rst       ),
    .rq_oper_data_ex    ( rq_oper_data_ex   ),
    .rq_oper_data       ( rq_oper_data      ),
    .rq_oper_wen        ( rq_oper_wen       ),
    .rq_oper_ready      ( rq_oper_ready     ),

//    .cap_rq_data        ( cap_rq_data       ),
//    .cap_rq_wen         ( cap_rq_wen        ),
    .odbg_info          ( dbg_rq_info       )
);


pcie_rc_intf #(
    .DWIDTH             ( DWIDTH            )
) u_pcie_rc_intf(
    .pcie_clk           ( pcie_clk          ),
    .pcie_rst           ( pcie_rst          ),
    .pcie_link_up       ( pcie_link_up      ),

    .m_axis_rc_tdata    ( m_axis_rc_tdata   ),
    .m_axis_rc_tuser    ( m_axis_rc_tuser   ),
    .m_axis_rc_tlast    ( m_axis_rc_tlast   ),
    .m_axis_rc_tkeep    ( m_axis_rc_tkeep   ),
    .m_axis_rc_tvalid   ( m_axis_rc_tvalid  ),
    .m_axis_rc_tready   ( m_axis_rc_tready  ),

    .rc_cplr_data_ex    ( rc_cplr_data_ex   ),
    .rc_cplr_data       ( rc_cplr_data      ),
    .rc_cplr_wen        ( rc_cplr_wen       ),
    .rc_cplr_ready      ( rc_cplr_ready     ),

    .odbg_info          ( dbg_rc_info       )

);

pcie_cq_intf #(
    .DWIDTH             ( DWIDTH            )
)
u_pcie_cq_intf(
    .pcie_clk           ( pcie_clk          ),
    .pcie_rst           ( pcie_rst          ),
    .pcie_link_up       ( pcie_link_up      ),

    .m_axis_cq_tlast    ( m_axis_cq_tlast   ),
    .m_axis_cq_tdata    ( m_axis_cq_tdata   ),
    .m_axis_cq_tuser    ( m_axis_cq_tuser   ),
    .m_axis_cq_tkeep    ( m_axis_cq_tkeep   ),
    .m_axis_cq_tready   ( m_axis_cq_tready  ),
    .m_axis_cq_tvalid   ( m_axis_cq_tvalid  ),

    .cq_oper_data_ex    ( cq_oper_data_ex   ),
    .cq_oper_data       ( cq_oper_data      ),
    .cq_oper_wen        ( cq_oper_wen       ),
    .cq_oper_ready      ( cq_oper_ready     ),

//    .read_req           ( read_req          ),
//    .req_tag            ( req_tag           ),
//    .cap_cq_data        ( cap_cq_data       ),
//    .cap_cq_wen         ( cap_cq_wen        ),
    .odbg_info          ( dbg_cq_info       )
);

pcie_cc_intf #(
    .DWIDTH             ( DWIDTH            )
)
u_pcie_cc_intf(
    .pcie_clk           ( pcie_clk          ),
    .pcie_rst           ( pcie_rst          ),
    .pcie_link_up       ( pcie_link_up      ),

    .s_axis_cc_tdata    ( s_axis_cc_tdata   ),
    .s_axis_cc_tuser    ( s_axis_cc_tuser   ),
    .s_axis_cc_tlast    ( s_axis_cc_tlast   ),
    .s_axis_cc_tkeep    ( s_axis_cc_tkeep   ),
    .s_axis_cc_tvalid   ( s_axis_cc_tvalid  ),
    .s_axis_cc_tready   ( s_axis_cc_tready[0]),

    .user_clk           ( cc_user_clk       ),
    .user_rst           ( cc_user_rst       ),
    .cc_cplr_data_ex    ( cc_cplr_data_ex   ),
    .cc_cplr_data       ( cc_cplr_data      ),
    .cc_cplr_wen        ( cc_cplr_wen       ),
    .cc_cplr_ready      ( cc_cplr_ready     ),

//    .cap_cc_data        ( cap_cc_data       ),
//    .cap_cc_wen         ( cap_cc_wen        ),
    .odbg_info          ( dbg_cc_info       )

);


endmodule