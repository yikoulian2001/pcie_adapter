
class   app_tlp;
    typedef struct packed{
        bit         sop         ;
        bit         eop         ;
        bit         err         ;
        bit         rsv1        ;
        bit [43:0]  userinfo    ;
        bit [2:0]   mtype       ;
        bit [4:0]   rsv0        ;
        bit [7:0]   rid         ;
        bit [15:0]  req_len     ;
        bit [63:0]  addr        ;
    }app_head;

    app_head  app_header;
    DW app_data[$];

endclass