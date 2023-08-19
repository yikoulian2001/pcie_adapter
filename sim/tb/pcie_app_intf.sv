
interface pcie_app_if;
    logic                   app_clk             ;
    //rq interface
    logic                   pcie_tx_ready       ;
    logic   [143:0]         pcie_tx_headin      ;
    logic                   pcie_tx_Hwrreq      ;
    logic   [DWIDTH-1:0]    pcie_tx_datain      ;
    logic                   pcie_tx_wrreq       ;

    logic                   pcie_rx_ready       ;
    logic   [143:0]         pcie_rx_headin      ;
    logic                   pcie_rx_Hwrreq      ;
    logic   [DWIDTH-1:0]    pcie_rx_datain      ;
    logic                   pcie_rx_wrreq       ;


    task automatic app_init;
        pcie_rx_ready = 0;

        pcie_tx_headin = 0;
        pcie_tx_Hwrreq = 0;
        pcie_tx_datain = 0;
        pcie_tx_wrreq  = 0;

    endtask

endinterface



class pcie_app_agent;

    virtual pcie_app_if u_pcie_app_if;

    mailbox #(app_tlp) apptlps_tx;
    mailbox #(app_tlp) apptlps_rx;




    function new(virtual pcie_app_if u_pcie_app_if);
        apptlps_tx = new();
        apptlps_rx = new();

        this.u_pcie_app_if = u_pcie_app_if;
    endfunction

    task run;
        fork
            tx_monitor;
            app_rx();
        join
    endtask



    task tx_monitor;

        app_tlp apptlp=new;

        forever
        begin
            this.apptlps_rx.get(apptlp);
//          $display("found cqtlp");
            app_tx(apptlp);
            apptlp=new;
        end
    endtask

    task automatic app_tx(app_tlp apptlp);
        int cnt=0;
        int rem=0;
//        u_pcie_axi_if.m_axis_rc_tuser<=0;


        if(apptlp.app_header.mtype==3'b000)     //write
        begin
            rem=apptlp.app_data.size%(DWIDTH/32);
            cnt=apptlp.app_data.size/(DWIDTH/32);

            if(rem!=0)cnt++;
            for(int i=0;i<cnt;i++)
            begin
                @(posedge u_pcie_app_if.app_clk);
                u_pcie_app_if.pcie_tx_wrreq <= 1;
                for(int k=0;k<DWIDTH/32;k++)
                    u_pcie_app_if.pcie_tx_datain[k*32+:32] <= apptlp.app_data[i*(DWIDTH/32)+k];

                if(i==cnt-1)
                begin
                    u_pcie_app_if.pcie_tx_Hwrreq <= 1;
                    u_pcie_app_if.pcie_tx_headin <= apptlp.app_header;
                end
                else
                    u_pcie_app_if.pcie_tx_Hwrreq <= 0;
            end
        end
        else if(apptlp.app_header.mtype==3'b010)    //read
        begin
            @(posedge u_pcie_app_if.app_clk);
            u_pcie_app_if.pcie_tx_Hwrreq <= 1;
            u_pcie_app_if.pcie_tx_headin <= apptlp.app_header;
        end
        @(posedge u_pcie_app_if.app_clk);
        u_pcie_app_if.pcie_tx_wrreq <= 0;
        u_pcie_app_if.pcie_tx_Hwrreq <= 0;
    endtask


    task automatic app_rx();
        app_tlp apptlp_t;

        apptlp_t=new;

        forever
        begin
            @( posedge u_pcie_app_if.app_clk);
//          u_pcie_app_if.pcie_rx_ready <= $urandom;
            u_pcie_app_if.pcie_rx_ready <= 1;
            if(u_pcie_app_if.pcie_rx_wrreq & u_pcie_app_if.pcie_rx_ready)
            begin
                for(int i=0;i<DWIDTH/32;i++)
                    apptlp_t.app_data.push_back(u_pcie_app_if.pcie_rx_datain[i*32+:32]);
            end

            if(u_pcie_app_if.pcie_rx_Hwrreq & u_pcie_app_if.pcie_rx_ready)
            begin
                apptlp_t.app_header = u_pcie_app_if.pcie_rx_headin;
                this.apptlps_tx.put(apptlp_t);
                apptlp_t=new;
            end
        end
    endtask


endclass