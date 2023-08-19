//`include "parameter.sv"
//`include "pcie_ut_tlps.sv"

interface pcie_axi_if;
    logic                       pcie_clk            ;
    //rq接口
    logic                       s_axis_rq_tlast     ;
    logic       [DWIDTH-1:0]    s_axis_rq_tdata     ;
    logic       [61:0]          s_axis_rq_tuser     ;
    logic       [DWIDTH/32-1:0] s_axis_rq_tkeep     ;
    logic                       s_axis_rq_tready    ;
    logic                       s_axis_rq_tvalid    ;
    //rc接口
    logic       [DWIDTH-1:0]    m_axis_rc_tdata     ;
    logic       [74:0]          m_axis_rc_tuser     ;
    logic                       m_axis_rc_tlast     ;
    logic       [DWIDTH/32-1:0] m_axis_rc_tkeep     ;
    logic                       m_axis_rc_tvalid    ;
    logic                       m_axis_rc_tready    ;
    //cq接口
    logic                       m_axis_cq_tlast     ;
    logic       [DWIDTH-1:0]    m_axis_cq_tdata     ;
    logic       [87:0]          m_axis_cq_tuser     ;
    logic       [DWIDTH/32-1:0] m_axis_cq_tkeep     ;
    logic                       m_axis_cq_tready    ;
    logic                       m_axis_cq_tvalid    ;
    //cc接口
    logic       [DWIDTH-1:0]    s_axis_cc_tdata     ;
    logic       [32:0]          s_axis_cc_tuser     ;
    logic                       s_axis_cc_tlast     ;
    logic       [DWIDTH/32-1:0] s_axis_cc_tkeep     ;
    logic                       s_axis_cc_tvalid    ;
    logic                       s_axis_cc_tready    ;


    task automatic axi_init;
        s_axis_rq_tready = 0;

        m_axis_rc_tdata  = 0;
        m_axis_rc_tuser  = 0;
        m_axis_rc_tlast  = 0;
        m_axis_rc_tkeep  = 0;
        m_axis_rc_tvalid = 0;

        m_axis_cq_tlast  = 0;
        m_axis_cq_tdata  = 0;
        m_axis_cq_tuser  = 0;
        m_axis_cq_tkeep  = 0;
        m_axis_cq_tvalid = 0;

        s_axis_cc_tready = 0;

    endtask

endinterface






class pcie_axi_agent;

    virtual pcie_axi_if u_pcie_axi_if;

    mailbox #(rq_tlp) rqtlps_tx;
    mailbox #(rc_tlp) rctlps_rx;
    mailbox #(cq_tlp) cqtlps_rx;
    mailbox #(cc_tlp) cctlps_tx;


//  function new(virtual pcie_axi_if u_pcie_axi_if,
//               mailbox #(rq_tlp) rqtlps,
//               mailbox #(rc_tlp) rctlps,
//               mailbox #(cq_tlp) cqtlps,
//               mailbox #(cc_tlp) cctlps);
//      rqtlps_tx=new(1);
//      rctlps_rx=new(1);
//      cqtlps_rx=new(1);
//      cctlps_tx=new(1);
//
//        this.u_pcie_axi_if = u_pcie_axi_if;
//        rqtlps = this.rqtlps_tx;
//        this.rctlps_rx = rctlps;
//        this.cqtlps_rx = cqtlps;
//        cctlps = this.cctlps_tx;
//    endfunction

    function new(virtual pcie_axi_if u_pcie_axi_if);
        rqtlps_tx = new();
        rctlps_rx = new();
        cqtlps_rx = new();
        cctlps_tx = new();

        this.u_pcie_axi_if = u_pcie_axi_if;
    endfunction

    task run;
        fork
            user_rq_rd();
            user_cc_rd();
            rc_monitor;
            cq_monitor;
        join
    endtask

    task rc_monitor;
        int cnt=0;
        rc_tlp rctlp=new;

        forever
        begin
            this.rctlps_rx.get(rctlp);

            user_rc_wr(rctlp);
            rctlp=new;
            cnt++;
            $display("rctlps_rx cnt = %d",cnt);
        end
    endtask
    task cq_monitor;

        cq_tlp cqtlp=new;

        forever
        begin
            this.cqtlps_rx.get(cqtlp);
//          $display("found cqtlp");
            user_cq_wr(cqtlp);
            cqtlp=new;
        end
    endtask

    task automatic user_rc_wr(rc_tlp rctlp);
        int cnt=0;
        int rem=0;
//        u_pcie_axi_if.m_axis_rc_tuser<=0;//不适用tuser

        if(DWIDTH==256)
        begin
            rem=rctlp.size%8;
            cnt=rctlp.size/8;
        end
        else if(DWIDTH==128)
        begin
            rem=rctlp.size%4;
            cnt=rctlp.size/4;
        end

        if(rem!=0)cnt++;
        for(int i=0;i<cnt;i++)
        begin
            @(posedge u_pcie_axi_if.pcie_clk);
            u_pcie_axi_if.m_axis_rc_tvalid <= 1;

            if(DWIDTH==256)
                u_pcie_axi_if.m_axis_rc_tdata <= {rctlp.get(i*8+7),rctlp.get(i*8+6),rctlp.get(i*8+5),rctlp.get(i*8+4),
                                                  rctlp.get(i*8+3),rctlp.get(i*8+2),rctlp.get(i*8+1),rctlp.get(i*8)};
            else if(DWIDTH==128)
                u_pcie_axi_if.m_axis_rc_tdata <= {rctlp.get(i*4+3),rctlp.get(i*4+2),rctlp.get(i*4+1),rctlp.get(i*4)};


            if(i==0)
                u_pcie_axi_if.m_axis_rc_tuser <= 75'h100000000;
            else
                u_pcie_axi_if.m_axis_rc_tuser <= 75'b0;

            if(i==cnt-1)
            begin
                u_pcie_axi_if.m_axis_rc_tlast <= 1;
                if(DWIDTH==256)
                begin
                    if(rem==1)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b0000_0001;
                    if(rem==2)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b0000_0011;
                    if(rem==3)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b0000_0111;
                    if(rem==4)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b0000_1111;
                    if(rem==5)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b0001_1111;
                    if(rem==6)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b0011_1111;
                    if(rem==7)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b0111_1111;
                    if(rem==0)u_pcie_axi_if.m_axis_rc_tkeep <= 8'b1111_1111;
                end
                else if(DWIDTH==128)
                begin
                    if(rem==1)u_pcie_axi_if.m_axis_rc_tkeep <= 4'b0001;
                    if(rem==2)u_pcie_axi_if.m_axis_rc_tkeep <= 4'b0011;
                    if(rem==3)u_pcie_axi_if.m_axis_rc_tkeep <= 4'b0111;
                    if(rem==0)u_pcie_axi_if.m_axis_rc_tkeep <= 4'b1111;
                end
            end
            else
            begin
                u_pcie_axi_if.m_axis_rc_tlast <= 0;
                u_pcie_axi_if.m_axis_rc_tkeep <= {(DWIDTH/32){1'b1}};
            end
        end
        @(posedge u_pcie_axi_if.pcie_clk);
        u_pcie_axi_if.m_axis_rc_tvalid <= 0;
        u_pcie_axi_if.m_axis_rc_tlast <= 0;
    endtask


    task automatic user_rq_rd();
        rq_tlp rq_tlp_t;
        bit sop=1;
        bit sop_1d=0;
        rq_tlp_t=new;

        forever
        begin
            @( posedge u_pcie_axi_if.pcie_clk);
            u_pcie_axi_if.s_axis_rq_tready <= $urandom;
//            u_pcie_axi_if.s_axis_rq_tready <= 1;
            if(u_pcie_axi_if.s_axis_rq_tvalid & u_pcie_axi_if.s_axis_rq_tready)
            begin
                if(DWIDTH==256)
                begin
                    if(sop)
                    begin
                        rq_tlp_t.rq_header={u_pcie_axi_if.s_axis_rq_tdata[127:96],u_pcie_axi_if.s_axis_rq_tdata[95:64],u_pcie_axi_if.s_axis_rq_tdata[63:32],u_pcie_axi_if.s_axis_rq_tdata[31:0]};
                        rq_tlp_t.first_be = u_pcie_axi_if.s_axis_rq_tuser[3:0];
                        rq_tlp_t.last_be = u_pcie_axi_if.s_axis_rq_tuser[7:4];
                        if(u_pcie_axi_if.s_axis_rq_tkeep[4])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[159:128]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[5])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[191:160]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[6])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[223:192]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[7])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[255:224]);
                    end
                    else
                    begin
                        if(u_pcie_axi_if.s_axis_rq_tkeep[0])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[31:0]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[1])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[63:32]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[2])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[95:64]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[3])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[127:96]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[4])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[159:128]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[5])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[191:160]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[6])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[223:192]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[7])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[255:224]);
                    end
                end
                else if(DWIDTH==128)
                begin
                    if(sop)
                    begin
                        rq_tlp_t.rq_header={u_pcie_axi_if.s_axis_rq_tdata[127:96],u_pcie_axi_if.s_axis_rq_tdata[95:64],u_pcie_axi_if.s_axis_rq_tdata[63:32],u_pcie_axi_if.s_axis_rq_tdata[31:0]};
                        rq_tlp_t.first_be = u_pcie_axi_if.s_axis_rq_tuser[3:0];
                        rq_tlp_t.last_be = u_pcie_axi_if.s_axis_rq_tuser[7:4];
                    end
                    else
                    begin
                        if(u_pcie_axi_if.s_axis_rq_tkeep[0])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[31:0]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[1])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[63:32]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[2])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[95:64]);
                        if(u_pcie_axi_if.s_axis_rq_tkeep[3])rq_tlp_t.rq_data.push_back(u_pcie_axi_if.s_axis_rq_tdata[127:96]);
                    end
                end

                sop_1d = sop;
                sop=0;
//                $display("rq_data = %32h",u_pcie_axi_if.s_axis_rq_tdata);
                if(u_pcie_axi_if.s_axis_rq_tlast)
                begin
//                     rqtlps.push_back(rq_tlp_t);
                     this.rqtlps_tx.put(rq_tlp_t);
//                     $display("rqtlps_size = %d",rqtlps.size);
                     rq_tlp_t=new;
                     sop=1;
                     sop_1d=0;
                end
            end
        end
    endtask




    task automatic user_cq_wr(cq_tlp cqtlp);
        int cnt=0;
        int rem=0;


//        u_pcie_axi_if.m_axis_cq_tuser<=0;//不适用tuser
        if(DWIDTH==256)begin
            rem=cqtlp.size%8;
            cnt=cqtlp.size/8;
        end else if(DWIDTH==128)begin
            rem=cqtlp.size%4;
            cnt=cqtlp.size/4;
        end else if(DWIDTH==64)begin
            rem=cqtlp.size%2;
            cnt=cqtlp.size/2;
        end
        if(rem!=0)cnt++;
        wait(u_pcie_axi_if.m_axis_cq_tready);

        for(int i=0;i<cnt;i++)
        begin
            @(posedge u_pcie_axi_if.pcie_clk);
            if(u_pcie_axi_if.m_axis_cq_tready)
            begin
                u_pcie_axi_if.m_axis_cq_tvalid <= 1;
                if(DWIDTH==256)
                    u_pcie_axi_if.m_axis_cq_tdata <= {cqtlp.get(i*8+7),cqtlp.get(i*8+6),cqtlp.get(i*8+5),cqtlp.get(i*8+4),
                                                      cqtlp.get(i*8+3),cqtlp.get(i*8+2),cqtlp.get(i*8+1),cqtlp.get(i*8)};
                else if(DWIDTH==128)
                    u_pcie_axi_if.m_axis_cq_tdata <= {cqtlp.get(i*4+3),cqtlp.get(i*4+2),cqtlp.get(i*4+1),cqtlp.get(i*4)};


                if(i==0)
                    u_pcie_axi_if.m_axis_cq_tuser <= {47'b0,1'b1,32'b0,cqtlp.last_be,cqtlp.first_be};
                else
                    u_pcie_axi_if.m_axis_cq_tuser <= 88'b0;

                if(i==cnt-1)
                begin
                    u_pcie_axi_if.m_axis_cq_tlast <= 1;
                    if(DWIDTH==256)
                    begin
                        if(rem==1)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b0000_0001;
                        if(rem==2)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b0000_0011;
                        if(rem==3)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b0000_0111;
                        if(rem==4)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b0000_1111;
                        if(rem==5)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b0001_1111;
                        if(rem==6)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b0011_1111;
                        if(rem==7)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b0111_1111;
                        if(rem==0)u_pcie_axi_if.m_axis_cq_tkeep <= 8'b1111_1111;
                    end
                    else if(DWIDTH==128)
                    begin
                        if(rem==1)u_pcie_axi_if.m_axis_cq_tkeep <= 4'b0001;
                        if(rem==2)u_pcie_axi_if.m_axis_cq_tkeep <= 4'b0011;
                        if(rem==3)u_pcie_axi_if.m_axis_cq_tkeep <= 4'b0111;
                        if(rem==0)u_pcie_axi_if.m_axis_cq_tkeep <= 4'b1111;
                    end

                end
                else
                begin
                    u_pcie_axi_if.m_axis_cq_tlast <= 0;
                    u_pcie_axi_if.m_axis_cq_tkeep <= {(DWIDTH/32){1'b1}};
                end
            end
            else
                i--;
        end
        @(posedge u_pcie_axi_if.pcie_clk);
        u_pcie_axi_if.m_axis_cq_tvalid <= 0;
        u_pcie_axi_if.m_axis_cq_tlast <= 0;
    endtask


    task automatic user_cc_rd();
        cc_tlp cc_tlp_t;
        bit sop=1;
        bit sop_1d=0;
        cc_tlp_t=new;

        forever
        begin
            @( posedge u_pcie_axi_if.pcie_clk);
//          u_pcie_axi_if.s_axis_cc_tready <= $urandom;
            u_pcie_axi_if.s_axis_cc_tready <= 1;
            if(u_pcie_axi_if.s_axis_cc_tvalid & u_pcie_axi_if.s_axis_cc_tready)
            begin
                if(DWIDTH==256)
                begin
                    if(sop)
                    begin
                        cc_tlp_t.cc_header={u_pcie_axi_if.s_axis_cc_tdata[95:64],u_pcie_axi_if.s_axis_cc_tdata[63:32],u_pcie_axi_if.s_axis_cc_tdata[31:0]};
//                      cc_tlp_t.first_be = u_pcie_axi_if.s_axis_cc_tuser[3:0];
//                      cc_tlp_t.last_be = u_pcie_axi_if.s_axis_cc_tuser[7:4];
                        if(u_pcie_axi_if.s_axis_cc_tkeep[3])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[127:96]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[4])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[159:128]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[5])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[191:160]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[6])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[223:192]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[7])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[255:224]);
//                        if(cc_tlp_t.cc_header.dw_cnt==1)
//                          $display("rd_start_addr = %8h, data = %8h",cc_tlp_t.cc_header.addr,u_pcie_axi_if.s_axis_cc_tdata[127:96]);
                    end
                    else
                    begin
                        if(u_pcie_axi_if.s_axis_cc_tkeep[0])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[31:0]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[1])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[63:32]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[2])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[95:64]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[3])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[127:96]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[4])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[159:128]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[5])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[191:160]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[6])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[223:192]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[7])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[255:224]);
                    end
                end
                else if(DWIDTH==128)
                begin
                    if(sop)
                    begin
                        cc_tlp_t.cc_header={u_pcie_axi_if.s_axis_cc_tdata[95:64],u_pcie_axi_if.s_axis_cc_tdata[63:32],u_pcie_axi_if.s_axis_cc_tdata[31:0]};
//                      cc_tlp_t.first_be = u_pcie_axi_if.s_axis_cc_tuser[3:0];
//                      cc_tlp_t.last_be = u_pcie_axi_if.s_axis_cc_tuser[7:4];
                        if(u_pcie_axi_if.s_axis_cc_tkeep[3])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[127:96]);
//                        if(cc_tlp_t.cc_header.dw_cnt==1)
//                          $display("rd_start_addr = %8h, data = %8h",cc_tlp_t.cc_header.addr,u_pcie_axi_if.s_axis_cc_tdata[127:96]);
                    end
                    else
                    begin
                        if(u_pcie_axi_if.s_axis_cc_tkeep[0])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[31:0]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[1])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[63:32]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[2])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[95:64]);
                        if(u_pcie_axi_if.s_axis_cc_tkeep[3])cc_tlp_t.cc_data.push_back(u_pcie_axi_if.s_axis_cc_tdata[127:96]);
                    end
                end

                sop_1d = sop;
                sop=0;
//                $display("cc_data = %32h",u_pcie_axi_if.s_axis_cc_tdata);
                if(u_pcie_axi_if.s_axis_cc_tlast)
                begin
//                     cctlps.push_back(cc_tlp_t);
                     this.cctlps_tx.put(cc_tlp_t);
                     cc_tlp_t=new;
                     sop=1;
                     sop_1d=0;
                end
            end
        end
    endtask

endclass



