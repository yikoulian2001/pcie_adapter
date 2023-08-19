
typedef bit[31:0] DW;

class   tlp_def;
    const static bit[3:0]  TLP_MEM_RD  = 4'b0000;
    const static bit[3:0]  TLP_MEM_WR  = 4'b0001;
    const static bit[3:0]  TLP_CFG0_RD = 4'b1000;
    const static bit[3:0]  TLP_CFG1_RD = 4'b1001;
    const static bit[3:0]  TLP_CFG0_WR = 4'b1010;
    const static bit[3:0]  TLP_CFG1_WR = 4'b1011;
endclass

class   rq_tlp;
    typedef struct packed{
        bit         force_ecrc  ;
        bit [2:0]   attr        ;
        bit [2:0]   tc          ;
        bit         rid_en      ;
        bit [15:0]  cid         ;
        bit [7:0]   tag         ;
        bit [15:0]  rid         ;
        bit         poison      ;
        bit [3:0]   req_type    ;
        bit [10:0]  dw_cnt      ;
        bit [61:0]  addr        ;
        bit [1:0]   at          ;
    }rq_des;

    bit [3:0]   first_be;
    bit [3:0]   last_be;

    rq_des  rq_header;
    DW rq_data[$];

    function DW get(int i);
        if(i==0)return rq_header[31:0];
        else if(i==1)return rq_header[63:32];
        else if(i==2)return rq_header[95:64];
        else if(i==3)return rq_header[127:96];
        else return rq_data[i-4];
    endfunction

    function int size;
        return 4 + rq_data.size;
    endfunction

    function void fprint(integer log);
        $fdisplay(log,"request---tag:%h,req_type:%4b,dw_cnt:%h,first_be:%4b,last_be:%4b,addr:%8h",
                    rq_header.tag,rq_header.req_type,rq_header.dw_cnt,first_be,last_be,{rq_header.addr,rq_header.at});
        for(int i=4;i<this.size;i++)
            $fdisplay(log,"address = %8h, data = %8h",(rq_header.addr+i-4)*4,this.get(i));
    endfunction
endclass

class   rc_tlp;
    typedef struct packed{
        bit         rsv0;
        bit [2:0]   attr;
        bit [2:0]   tc;
        bit         rsv1;
        bit [15:0]  cid;
        bit [7:0]   tag;
        bit [15:0]  rid;
        bit         rsv2;
        bit         poison;
        bit [2:0]   cpl_status;
        bit [10:0]  dw_cnt;
        bit         rsv3;
        bit         req_completed;
        bit         locked_rd_cpl;
        bit [12:0]  byte_cnt;
        bit [3:0]   error_code;
        bit [11:0]  addr;
    }rc_des;

    rc_des rc_header;
    DW rc_data[$];

    function DW get(int i);
        if(i==0)return rc_header[31:0];
        else if(i==1)return rc_header[63:32];
        else if(i==2)return rc_header[95:64];
        else return rc_data[i-3];
    endfunction

    function int size;
        return 3+rc_data.size;
    endfunction

    function void fprint(integer log);
        $fdisplay(log,"completion---tag:%h,dw_cnt:%h,addr:%8h",
                    rc_header.tag,rc_header.dw_cnt,rc_header.addr);
        for(int i=3;i<this.size;i++)
            $fdisplay(log,"address = %8h, data = %8h",((rc_header.addr/4)+i-3)*4,this.get(i));
    endfunction
endclass

class   cq_tlp;
    typedef struct packed{
        bit         rsv0        ;
        bit [2:0]   attr        ;
        bit [2:0]   tc          ;
        bit [5:0]   bar_Aperture;
        bit [2:0]   bar_id      ;
        bit [7:0]   target_func ;
        bit [7:0]   tag         ;
        bit [15:0]  rid         ;
        bit         rsv1        ;
        bit [3:0]   req_type    ;
        bit [10:0]  dw_cnt      ;
        bit [61:0]  addr        ;
        bit [1:0]   at          ;
    }cq_des;

    bit [3:0]   first_be;
    bit [3:0]   last_be;

    cq_des  cq_header;
    bit[31:0] cq_data[$];

    function bit[31:0] get(int i);
        if(i==0)return cq_header[31:0];
        else if(i==1)return cq_header[63:32];
        else if(i==2)return cq_header[95:64];
        else if(i==3)return cq_header[127:96];
        else return cq_data[i-4];
    endfunction

    function int size;
        return 4 + cq_data.size;
    endfunction

    function void fprint(integer log);
        $fdisplay(log,"request---tag:%h,req_type:%4b,dw_cnt:%h,first_be:%4b,last_be:%4b,addr:%8h",
                    cq_header.tag,cq_header.req_type,cq_header.dw_cnt,first_be,last_be,{cq_header.addr,cq_header.at});
        for(int i=4;i<this.size;i++)
            $fdisplay(log,"address = %8h, data = %8h",(cq_header.addr+i-4)*4,this.get(i));
    endfunction
endclass

class   cc_tlp;
    typedef struct packed{
        bit         force_ecrc;
        bit [2:0]   attr;
        bit [2:0]   tc;
        bit         cpld_id_en;
        bit [15:0]  cid;
        bit [7:0]   tag;
        bit [15:0]  rid;
        bit         rsv0;
        bit         poison;
        bit [2:0]   cpl_status;
        bit [10:0]  dw_cnt;
        bit [1:0]   rsv1;
        bit         locked_rd_cpl;
        bit [12:0]  byte_cnt;
        bit [5:0]   rsv2;
        bit [1:0]   at;
        bit         rsv3;
        bit [6:0]   addr;
    }cc_des;

    cc_des cc_header;
    bit[31:0] cc_data[$];

    function bit[31:0] get(int i);
        if(i==0)return cc_header[31:0];
        else if(i==1)return cc_header[63:32];
        else if(i==2)return cc_header[95:64];
        else return cc_data[i-3];
    endfunction

    function int size;
        return 3+cc_data.size;
    endfunction

    function void fprint(integer log);
        $fdisplay(log,"completion---tag:%h,dw_cnt:%h,addr:%8h",
                    cc_header.tag,cc_header.dw_cnt,cc_header.addr);
        for(int i=3;i<this.size;i++)
            $fdisplay(log,"address = %8h, data = %8h",((cc_header.addr/4)+i-3)*4,this.get(i));
    endfunction
endclass



