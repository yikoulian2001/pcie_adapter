
//`include "pcie_ut_intf.sv"

class pcie_agent;

//    static bit[7:0] MEMORY[bit[63:0]];

    mailbox #(rq_tlp) rqtlps_rx;
    mailbox #(rc_tlp) rctlps_tx;
    mailbox #(cq_tlp) cqtlps_tx;
    mailbox #(cc_tlp) cctlps_rx;
    mailbox #(app_tlp) apptlps_tx;
    mailbox #(app_tlp) apptlps_rx;
    rq_tlp rdtlps[256];
    cc_tlp cctlps[$];

    app_tlp apptlps_w[$];
    int rc_cnt=0;

    function new();
        rqtlps_rx=new();
        rctlps_tx=new();
        cqtlps_tx=new();
        cctlps_rx=new();
        apptlps_tx=new();
        apptlps_rx=new();
    endfunction


    task run;
        for(int k=0;k<256;k++)
            rdtlps[k]=new;
        fork

            axi_monitor;
            search_rd_tag;
            app_monitor;


        join
    endtask

    task axi_monitor;
        rq_tlp rqtlp=new;
        int tag;
        forever
        begin

            this.rqtlps_rx.get(rqtlp);


//          $display("req_type = %d,WR_type = $d",rqtlp.rq_header.req_type,tlp_def::TLP_MEM_WR);
            tag = rqtlp.rq_header.tag;
            if(rqtlp.rq_header.req_type==tlp_def::TLP_MEM_WR)
            begin
                mwr(rqtlp);
            end

            if(rqtlp.rq_header.req_type==tlp_def::TLP_MEM_RD)
            begin
                mrd(rqtlp,rdtlps[tag]);
            end
            rqtlp=new;
        end
    endtask

    task app_monitor;
        app_tlp apptlp=new;

        forever
        begin
            this.apptlps_rx.get(apptlp);
            app_compare(apptlp);
            apptlp=new;
        end
    endtask






    task  mwr(rq_tlp rqtlp);
        bit[63:0] start_addr;
        int first_offset;
        int last_offset;
        int last_offset_pre;
        int byte_len;
        int cnt,rem;

        if(rqtlp.rq_header.req_type!=tlp_def::TLP_MEM_WR)return;
//        if(int_check(rqtlp))return;
//        //vt_d虚实地址转换
//        start_addr=vt_d(rqtlp.rq_header.rid,rqtlp.rq_header.addr,rqtlp.rq_header.at);
        start_addr = {rqtlp.rq_header.addr,2'b0};
        casez(rqtlp.first_be)
        4'b1000 :   first_offset = 3;
        4'b?100 :   first_offset = 2;
        4'b??10 :   first_offset = 1;
        default :   first_offset = 0;
        endcase

        casez(rqtlp.first_be)
        4'b01?? :   last_offset_pre = 1;
        4'b001? :   last_offset_pre = 2;
        4'b0001 :   last_offset_pre = 3;
        default :   last_offset_pre = 0;
        endcase

        casez(rqtlp.last_be)
        4'b0001 :   last_offset = 3;
        4'b001? :   last_offset = 2;
        4'b01?? :   last_offset = 1;
        default :   last_offset = 0;
        endcase

        byte_len = rqtlp.rq_header.dw_cnt * 4 - first_offset - last_offset - last_offset_pre;

        if(rqtlp.rq_header.dw_cnt==1 && rqtlp.first_be==0 && rqtlp.last_be==0)
            $display("write 0 byte operation");
        else if(rqtlp.rq_header.dw_cnt!=rqtlp.rq_data.size)
        begin
            $display("-----fatal err, malformed tlp---");
            $stop;
        end

//        $display("wr_start_addr = %8h",start_addr);
        for(int i=0;i<byte_len;i++)
        begin
            cnt = (i+first_offset)/4;
            rem = (i+first_offset)%4;
            if(rem==0) MEMORY[start_addr+i+first_offset]=rqtlp.rq_data[cnt][7:0];
            if(rem==1) MEMORY[start_addr+i+first_offset]=rqtlp.rq_data[cnt][15:8];
            if(rem==2) MEMORY[start_addr+i+first_offset]=rqtlp.rq_data[cnt][23:16];
            if(rem==3) MEMORY[start_addr+i+first_offset]=rqtlp.rq_data[cnt][31:24];
        end
    endtask

    task mrd(rq_tlp rqtlp,ref rq_tlp rdtlp);

        bit[63:0] start_addr;
        int dw_cnt;
        int first_offset;
        int last_offset;
        int last_offset_pre;

//        int curr_byte_cnt;
//        int bytes_left;



        if(rqtlp.rq_header.req_type!=tlp_def::TLP_MEM_RD)
            return;

//        start_addr=vt_d(rqtlp.rq_header.rid,rqtlp.rq_header.addr,rqtlp.rq_header.at);
        start_addr = {rqtlp.rq_header.addr,2'b0};

        rdtlp.rq_header = rqtlp.rq_header;
        dw_cnt = rqtlp.rq_header.dw_cnt;

        for(int i=0;i<dw_cnt;i++)begin
//          $display("rd_start_addr = %8h, data = %4h",start_addr+i*4+3,MEMORY[start_addr+i*4+3]);
            rdtlp.rq_data.push_back({MEMORY[start_addr+i*4+3],MEMORY[start_addr+i*4+2],MEMORY[start_addr+i*4+1],MEMORY[start_addr+i*4]});
        end

    endtask



    task search_rd_tag;

        int tag=MAXTAG-1;



        forever
        begin

`ifndef RAND_TAG
            if(tag==MAXTAG-1)
                tag = 0;
            else
                tag = tag + 1;

`else
            tag = $urandom_range(0,MAXTAG-1);
`endif
            wait(rdtlps[tag].rq_data.size!=0);



            cpl_gen(rdtlps[tag]);
            rdtlps[tag]=new;

            #1ns;
        end
    endtask


    task cpl_gen(rq_tlp rdtlp);
        bit[63:0] start_addr;
        int dw_cnt;
        int first_offset;
        int last_offset;
        int last_offset_pre;

        int curr_byte_cnt;
        int bytes_left;

        int j;

        rc_tlp cpl;


        cpl=new;

        start_addr = {rdtlp.rq_header.addr,2'b0};
        casez(rdtlp.first_be)
        4'b1000 :   first_offset = 3;
        4'b?100 :   first_offset = 2;
        4'b??10 :   first_offset = 1;
        default :   first_offset = 0;
        endcase

        casez(rdtlp.first_be)
        4'b01?? :   last_offset_pre = 1;
        4'b001? :   last_offset_pre = 2;
        4'b0001 :   last_offset_pre = 3;
        default :   last_offset_pre = 0;
        endcase

        casez(rdtlp.last_be)
        4'b0001 :   last_offset = 3;
        4'b001? :   last_offset = 2;
        4'b01?? :   last_offset = 1;
        default :   last_offset = 0;
        endcase

        dw_cnt = rdtlp.rq_header.dw_cnt;

        cpl.rc_header.attr = rdtlp.rq_header.attr;
        cpl.rc_header.tc   = rdtlp.rq_header.tc;
        cpl.rc_header.tag  = rdtlp.rq_header.tag;
        cpl.rc_header.rid  = rdtlp.rq_header.rid;
        cpl.rc_header.cid  = 16'h4500;
        //如果生成多个cpl需要重新填充以下字段
`ifndef MULTI_CPL
        begin
            cpl.rc_header.dw_cnt        = dw_cnt;
            cpl.rc_header.req_completed = 1;
            cpl.rc_header.byte_cnt      = dw_cnt*4-first_offset-last_offset-last_offset_pre;
            cpl.rc_header.addr          = {rdtlp.rq_header.addr,first_offset[1:0]};


            for(int i=0;i<dw_cnt;i++)begin
//              $display("rd_start_addr = %8h, data = %4h",start_addr+i*4+3,MEMORY[start_addr+i*4+3]);
                cpl.rc_data.push_back(rdtlp.rq_data[i]);
            end
//            u_pcie_axi_agent.user_rc_wr(cpl);
            this.rctlps_tx.put(cpl);
            rc_cnt++;
            $display("rctlps_tx cnt = %d",rc_cnt);
//            cpl.fprint(cpl_mrd_log);
            return;
        end
`else
        bytes_left = dw_cnt*4-first_offset-last_offset-last_offset_pre;
        j=0;
        do begin
            if((start_addr[5:0] + dw_cnt*4)>64)
                curr_byte_cnt = 64 - start_addr[5:0];
            else
                curr_byte_cnt = dw_cnt*4;

            cpl.rc_header.dw_cnt = curr_byte_cnt/4;
            if(bytes_left <= (curr_byte_cnt - first_offset))
                cpl.rc_header.req_completed = 1;
            else
                cpl.rc_header.req_completed = 0;

            cpl.rc_header.attr = rdtlp.rq_header.attr;
            cpl.rc_header.tc   = rdtlp.rq_header.tc;
            cpl.rc_header.tag  = rdtlp.rq_header.tag;
            cpl.rc_header.rid  = rdtlp.rq_header.rid;
            cpl.rc_header.cid  =0;
            cpl.rc_header.byte_cnt = bytes_left;
            cpl.rc_header.addr     = {start_addr[63:2],first_offset[1:0]};

            for(int i=0;i<curr_byte_cnt/4;i++)
            begin
                cpl.rc_data.push_back(rdtlp.rq_data[j]);
                j++;
            end
//            u_pcie_axi_agent.user_rc_wr(cpl);
            this.rctlps_tx.put(cpl);
//            cpl.fprint(cpl_mrd_log);

            bytes_left = bytes_left - curr_byte_cnt + first_offset;
            start_addr = start_addr + curr_byte_cnt;
            dw_cnt = dw_cnt - curr_byte_cnt/4;
            first_offset = 0;
            cpl=new;
        end while(bytes_left>0);
`endif
    endtask


    task  pcie_wr_and_rd_adrs_add(int num,bit[63:0] start_adrs,int len_min,int len_max);
        app_tlp apptlp_t;

        bit[63:0] curr_addr;
        int len;
        int last_offset;
        int last_offset_pre;
        int byte_len;
        int cnt,rem;
        bit[43:0] usrinfo;

        apptlp_t=new;
        curr_addr = start_adrs;
        for(int i=0;i<num;i++)
        begin
            len = $urandom_range(len_min,len_max);
            usrinfo = $random;

            apptlp_t.app_header.sop      = 1;
            apptlp_t.app_header.eop      = 1;
            apptlp_t.app_header.err      = 0;
            apptlp_t.app_header.rsv1     = 0;
            apptlp_t.app_header.userinfo = usrinfo;
            apptlp_t.app_header.mtype    = 3'b000;      //write
            apptlp_t.app_header.rsv0     = 0;
            apptlp_t.app_header.rid      = 8'hab;
            apptlp_t.app_header.req_len  = len;
            apptlp_t.app_header.addr     = curr_addr;
            cnt = len/4;
            rem = len%4;
            if(rem!=0)  cnt++;
            while(cnt!=0)
            begin
                apptlp_t.app_data.push_back($random);
                cnt--;
            end
//          app_tx(app_tlp apptlp_t);
            this.apptlps_tx.put(apptlp_t);
            apptlps_w.push_back(apptlp_t);
            apptlp_t=new;
            #500ns;
            apptlp_t.app_header.sop      = 1;
            apptlp_t.app_header.eop      = 1;
            apptlp_t.app_header.err      = 0;
            apptlp_t.app_header.rsv1     = 0;
            apptlp_t.app_header.userinfo = usrinfo;
            apptlp_t.app_header.mtype    = 3'b010;      //read
            apptlp_t.app_header.rsv0     = 0;
            apptlp_t.app_header.rid      = 8'hab;
            apptlp_t.app_header.req_len  = len;
            apptlp_t.app_header.addr     = curr_addr;
//          app_tx(app_tlp apptlp_t);
            this.apptlps_tx.put(apptlp_t);
            apptlp_t=new;
            curr_addr = curr_addr + len;
        end

    endtask

    task app_compare(app_tlp apptlp_r);
        int i=0;
        int len;
        int cnt;
        int rem;
        DW  mask;
        app_tlp apptlp_w;
        apptlp_w=new;
        apptlp_w = apptlps_w.pop_front();
        if(apptlp_w.app_header!=apptlp_r.app_header)
        begin
            $display("-----compare err, header diff---");
            $display("write side header = %h",apptlp_w.app_header);
            $display("read side header = %h",apptlp_r.app_header);
            $stop;
        end

        len = apptlp_w.app_header.req_len;
        cnt = len/4;
        rem = len%4;
        if(rem!=0) cnt++;
        mask = (rem==0)? 32'hffffffff :
               (rem==1)? 32'h000000ff :
               (rem==2)? 32'h0000ffff :
                         32'h00ffffff;
//      $display("len = %h, cnt = %h, mask = %h",len,cnt,mask);
        while(i!=cnt)
        begin
            if(i==cnt-1 & (apptlp_w.app_data[i]&mask)!=(apptlp_r.app_data[i]&mask))
            begin
                $display("-----compare err, data diff---");
                $display("write side data = %h",apptlp_w.app_data[i]&mask);
                $display("read side data = %h",apptlp_r.app_data[i]&mask);
                $stop;
            end
            else if(i<cnt-1 & apptlp_w.app_data[i]!=apptlp_r.app_data[i])
            begin
                $display("-----compare err, data diff---");
                $display("write side data = %h",apptlp_w.app_data[i]);
                $display("read side data = %h",apptlp_r.app_data[i]);
                $stop;
            end
            i++;
        end

    endtask



//    task cfg_gen(bit[7:0] func,bit[2:0] bar,bit[7:0] cnt,bit[31:0] addr,bit wr,bit[31:0] data);
//
//        bit[3:0]    req_type = 0;
//        cq_tlp cqtlp;
//
//
//        cqtlp=new;
//
//
//
//        req_type = (wr)? 4'b0000 : 4'b0001; //0-写  1-读
//        if(~wr) cqtlp.cq_data.push_back(data);
//
//
//        cqtlp.cq_header.rsv0         = 0;
//        cqtlp.cq_header.attr         = 0;
//        cqtlp.cq_header.tc           = 0;
//        cqtlp.cq_header.bar_Aperture = 6'h12;
//        cqtlp.cq_header.bar_id       = bar;
//        cqtlp.cq_header.target_func  = func;
//        cqtlp.cq_header.tag          = cnt;
//        cqtlp.cq_header.rid          = 16'h0018;
//        cqtlp.cq_header.rsv1         = 0;
//        cqtlp.cq_header.req_type     = req_type;
//        cqtlp.cq_header.dw_cnt       = 1;
//        cqtlp.cq_header.addr         = {32'b0,addr[31:2]};
//        cqtlp.cq_header.at           = 0;
//
//        cqtlp.first_be = 4'hf;
//        cqtlp.last_be  = 4'b0;
////        $display("addr = %h",cqtlp.cq_header.addr);
//
//        this.cqtlps_tx.put(cqtlp);
////        u_pcie_axi_agent.user_cq_wr(cqtlp);
//
//        cqtlp=new;
////        if(wr)
////            wait(u_pcie_axi_agent.u_pcie_axi_if.s_axis_cc_tvalid==1 && u_pcie_axi_agent.u_pcie_axi_if.s_axis_cc_tlast==1);
////        else
////            ;
//
//    endtask
//
//
//    task init_cfg;  //0-写  1-读
//    bit[7:0] tag = 0;
//
//
//    #1us;
//    cfg_gen(8'h00,0,tag,32'h0000_0828,0,32'h00000001);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0030,0,32'h5a5a0001);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0030,0,32'h5a5a0000);
//    #300ns tag++;
//
//
//    cfg_gen(8'h00,0,tag,32'h0000_0000,1,32'h00000000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0004,1,32'h00000000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0008,1,32'h00000000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_000c,1,32'h00000000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0020,1,32'h00000002);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0020,0,32'h12345678);
//    #300ns tag++;
//    #1us;
//    cfg_gen(8'h00,0,tag,32'h0000_0020,1,32'h00000000);
//    #300ns tag++;
//
//    cfg_gen(8'h00,0,tag,32'h0000_0800,0,32'h00020000);  //32'h00000101
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0804,0,32'h0d040004);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_080c,0,32'h01100100);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_081c,0,32'h08008010);
//    #300ns tag++;
////    cfg_gen(8'h00,0,tag,32'h0000_0814,0,32'h00000000);
////    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0824,0,32'h01100c0c);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_082c,0,32'h00100000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0830,0,32'h00000000);
//    #300ns tag++;
//
//
//    cfg_gen(8'h00,0,tag,32'h0000_0204,0,32'h0ff00000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0208,0,32'h0bb00000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_020c,0,32'h0aa00000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0200,0,32'hffffffff);
//    #300ns tag++;
//
//    cfg_gen(8'h00,0,tag,32'h0000_0340,0,32'h00001234);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0344,0,32'h20000000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0348,0,32'h00001000);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_034c,0,32'h5a5a0001);
//    #300ns tag++;
//    cfg_gen(8'h00,0,tag,32'h0000_0350,1,32'h00000000);
//    #300ns tag++;
//
//
//    endtask


endclass





//30428066