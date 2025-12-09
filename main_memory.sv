module main_memory #(
    parameter ADDR_WIDTH  = 16,
    parameter BLOCK_BYTES = 32
)(
    input  logic                     clk,
    input  logic                     rst,

    // Interfaz por bloques
    input  logic [ADDR_WIDTH-1:0]    mem_addr_block,
    input  logic [BLOCK_BYTES*8-1:0] mem_wdata_block,
    input  logic                     mem_read,
    input  logic                     mem_write,
    output logic [BLOCK_BYTES*8-1:0] mem_rdata_block,
    output logic                     mem_ready
);

    localparam MEM_BYTES       = 65536; // 64 KiB
    localparam BLOCK_COUNT     = MEM_BYTES / BLOCK_BYTES;
    localparam BLOCK_ADDR_BITS = $clog2(BLOCK_COUNT);
    localparam OFFSET_BITS     = $clog2(BLOCK_BYTES);

    logic [BLOCK_BYTES*8-1:0] mem_array [0:BLOCK_COUNT-1];

    // Latch de la operacion
    logic                     busy;
    logic                     lat_is_read;
    logic                     lat_is_write;
    logic [BLOCK_ADDR_BITS-1:0] lat_block_index;
    logic [BLOCK_BYTES*8-1:0]   lat_wdata;
    integer                     latency_cnt;

    integer i;

    // Inicializacion con un patron conocido 
    initial begin
        for (i = 0; i < BLOCK_COUNT; i++) begin
            mem_array[i] = {8{32'h1000_0000 + i}}; // solo para debug
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy           <= 1'b0;
            mem_ready      <= 1'b0;
            lat_is_read    <= 1'b0;
            lat_is_write   <= 1'b0;
            latency_cnt    <= 0;
        end else begin
            mem_ready <= 1'b0; // pulso de 1 ciclo

            if (!busy) begin
                // Aceptamos una nueva operacion
                if (mem_read || mem_write) begin
                    busy         <= 1'b1;
                    lat_is_read  <= mem_read;
                    lat_is_write <= mem_write;
                    lat_block_index <= mem_addr_block[ADDR_WIDTH-1:OFFSET_BITS];
                    lat_wdata    <= mem_wdata_block;
                    latency_cnt  <= 2;  // latencia de 2 ciclos
                end
            end else begin
                // Estamos atendiendo una operacion previa
                if (latency_cnt > 0) begin
                    latency_cnt <= latency_cnt - 1;
                end else begin
                    // Ejecutar operacion
                    if (lat_is_read) begin
                        mem_rdata_block <= mem_array[lat_block_index];
                    end
                    if (lat_is_write) begin
                        mem_array[lat_block_index] <= lat_wdata;
                    end
                    mem_ready   <= 1'b1;
                    busy        <= 1'b0;
                end
            end
        end
    end

endmodule
