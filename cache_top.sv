module cache_top (
    input logic clk,
    input logic rst
);

    // Señales CPU al Cache
    logic [15:0] cpu_addr;
    logic [31:0] cpu_wdata;
    logic        cpu_read;
    logic        cpu_write;
    logic [31:0] cpu_rdata;
    logic        cpu_ready;
    logic        cpu_hit;

    // Señales CPU  Cache a Memoria
    logic [15:0]      mem_addr_block;
    logic [255:0]     mem_wdata_block;
    logic             mem_read;
    logic             mem_write;
    logic [255:0]     mem_rdata_block;
    logic             mem_ready;

    // Instancias
    cpu_dummy u_cpu (
        .clk       (clk),
        .rst       (rst),
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_wdata),
        .cpu_read  (cpu_read),
        .cpu_write (cpu_write),
        .cpu_rdata (cpu_rdata),
        .cpu_ready (cpu_ready),
        .cpu_hit   (cpu_hit)
    );

    data_cache u_cache (
        .clk            (clk),
        .rst            (rst),
        .cpu_addr       (cpu_addr),
        .cpu_wdata      (cpu_wdata),
        .cpu_read       (cpu_read),
        .cpu_write      (cpu_write),
        .cpu_rdata      (cpu_rdata),
        .cpu_ready      (cpu_ready),
        .cpu_hit        (cpu_hit),
        .mem_addr_block (mem_addr_block),
        .mem_wdata_block(mem_wdata_block),
        .mem_read       (mem_read),
        .mem_write      (mem_write),
        .mem_rdata_block(mem_rdata_block),
        .mem_ready      (mem_ready)
    );

    main_memory u_mem (
        .clk            (clk),
        .rst            (rst),
        .mem_addr_block (mem_addr_block),
        .mem_wdata_block(mem_wdata_block),
        .mem_read       (mem_read),
        .mem_write      (mem_write),
        .mem_rdata_block(mem_rdata_block),
        .mem_ready      (mem_ready)
    );

endmodule
