module data_cache #(
    parameter ADDR_WIDTH   = 16,
    parameter DATA_WIDTH   = 32,
    parameter BLOCK_BYTES  = 32,           // 256 bits
    parameter CACHE_BYTES  = 1024,
    parameter LINE_COUNT   = CACHE_BYTES / BLOCK_BYTES,
    parameter OFFSET_BITS  = $clog2(BLOCK_BYTES),
    parameter INDEX_BITS   = $clog2(LINE_COUNT),
    parameter TAG_BITS     = ADDR_WIDTH - OFFSET_BITS - INDEX_BITS
)(
    input  logic                   clk,
    input  logic                   rst,

    // Interfaz hacia la CPU
    input  logic [ADDR_WIDTH-1:0]  cpu_addr,
    input  logic [DATA_WIDTH-1:0]  cpu_wdata,
    input  logic                   cpu_read,
    input  logic                   cpu_write,
    output logic [DATA_WIDTH-1:0]  cpu_rdata,
    output logic                   cpu_ready,
    output logic                   cpu_hit,      // hit/miss de la ultima operacion

    // Interfaz hacia la memoria principal (por bloques)
    output logic [ADDR_WIDTH-1:0]    mem_addr_block,
    output logic [BLOCK_BYTES*8-1:0] mem_wdata_block,
    output logic                     mem_read,
    output logic                     mem_write,
    input  logic [BLOCK_BYTES*8-1:0] mem_rdata_block,
    input  logic                     mem_ready
);

    // =====================================================
    // Parametros derivados
    // =====================================================
    localparam WORD_BYTES    = DATA_WIDTH / 8;          // 4 bytes
    localparam WORDS_PER_BLK = BLOCK_BYTES / WORD_BYTES; // 8 palabras

    // =====================================================
    // Estructuras internas de la cache
    // =====================================================

    // Datos: 32 lineas x 256 bits
    logic [BLOCK_BYTES*8-1:0] data_array  [0:LINE_COUNT-1];

    // Tag: 6 bits por linea
    logic [TAG_BITS-1:0]      tag_array   [0:LINE_COUNT-1];

    // Valido y dirty: 1 bit por linea
    logic                      valid_array [0:LINE_COUNT-1];
    logic                      dirty_array [0:LINE_COUNT-1];

    // =====================================================
    // Registro de la solicitud de CPU
    // =====================================================
    logic [ADDR_WIDTH-1:0]   req_addr;
    logic [TAG_BITS-1:0]     req_tag;
    logic [INDEX_BITS-1:0]   req_index;
    logic [OFFSET_BITS-1:0]  req_offset;
    logic [2:0]              req_word_idx;   // 0..7
    logic                    req_is_read;
    logic                    req_is_write;
    logic [DATA_WIDTH-1:0]   req_wdata;

    // Para estadisticas y salida
    logic                    last_hit;

    // Tag/valid/dirty de la linea seleccionada
    logic [TAG_BITS-1:0]     line_tag;
    logic                    line_valid;
    logic                    line_dirty;

    // Tag de la linea victima (para write-back)
    logic [TAG_BITS-1:0]     victim_tag;

    // =====================================================
    // Funciones auxiliares para acceder a palabras en el bloque
    // =====================================================

    function automatic [DATA_WIDTH-1:0] get_word(
        input [BLOCK_BYTES*8-1:0] block,
        input [2:0]               word_idx
    );
        get_word = block[word_idx*DATA_WIDTH +: DATA_WIDTH];
    endfunction

    function automatic [BLOCK_BYTES*8-1:0] set_word(
        input [BLOCK_BYTES*8-1:0] block,
        input [2:0]               word_idx,
        input [DATA_WIDTH-1:0]    w
    );
        automatic logic [BLOCK_BYTES*8-1:0] tmp;
        tmp = block;
        tmp[word_idx*DATA_WIDTH +: DATA_WIDTH] = w;
        set_word = tmp;
    endfunction

    // =====================================================
    // Decodificacion de la direccion actual de CPU (para S_IDLE)
    // =====================================================
    logic [TAG_BITS-1:0]    addr_tag;
    logic [INDEX_BITS-1:0]  addr_index;
    logic [OFFSET_BITS-1:0] addr_offset;
    logic [2:0]             addr_word_idx;

    always_comb begin
        addr_tag      = cpu_addr[ADDR_WIDTH-1 -: TAG_BITS];
        addr_index    = cpu_addr[OFFSET_BITS +: INDEX_BITS];
        addr_offset   = cpu_addr[OFFSET_BITS-1:0];
        addr_word_idx = addr_offset[OFFSET_BITS-1:2]; // bits [4:2] para 32B bloque
    end

    // =====================================================
    // Lectura de la linea seleccionada por req_index
    // =====================================================
    always_comb begin
        line_tag   = tag_array[req_index];
        line_valid = valid_array[req_index];
        line_dirty = dirty_array[req_index];
    end

    // =====================================================
    // FSM
    // =====================================================

    typedef enum logic [2:0] {
        S_IDLE,
        S_LOOKUP,
        S_WRITEBACK,
        S_MEM_READ
    } state_t;

    state_t state, next_state;

    // Señal interna: hit basado en la solicitud latcheada
    logic hit_req;

    always_comb begin
        hit_req = (line_valid && (line_tag == req_tag));
    end

    // Control de peticion a memoria (pulso de 1 ciclo)
    logic        mem_req_sent;
    logic [ADDR_WIDTH-1:0]    mem_addr_reg;
    logic [BLOCK_BYTES*8-1:0] mem_wdata_reg;
    logic                     mem_do_read;
    logic                     mem_do_write;

    assign mem_addr_block   = mem_addr_reg;
    assign mem_wdata_block  = mem_wdata_reg;

    // Por defecto no pedimos nada
    assign mem_read  = (mem_do_read  && !mem_req_sent);
    assign mem_write = (mem_do_write && !mem_req_sent);

    // =====================================================
    // Logica secuencial
    // =====================================================
    integer i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            cpu_ready    <= 1'b0;
            cpu_rdata    <= '0;
            last_hit     <= 1'b0;
            mem_req_sent <= 1'b0;
            mem_do_read  <= 1'b0;
            mem_do_write <= 1'b0;
            mem_addr_reg <= '0;
            mem_wdata_reg<= '0;
            victim_tag   <= '0;

            for (i = 0; i < LINE_COUNT; i++) begin
                data_array[i]  <= '0;
                tag_array[i]   <= '0;
                valid_array[i] <= 1'b0;
                dirty_array[i] <= 1'b0;
            end
        end else begin
            cpu_ready    <= 1'b0;   // por defecto
            mem_req_sent <= mem_req_sent; // se actualiza mas abajo

            case (state)
                // -----------------------------------------
                S_IDLE: begin
                    mem_do_read  <= 1'b0;
                    mem_do_write <= 1'b0;
                    mem_req_sent <= 1'b0;

                    // Esperamos una solicitud valida de CPU
                    if ((cpu_read ^ cpu_write) && !(cpu_read && cpu_write)) begin
                        // Latch de la solicitud
                        req_addr      <= cpu_addr;
                        req_tag       <= addr_tag;
                        req_index     <= addr_index;
                        req_offset    <= addr_offset;
                        req_word_idx  <= addr_word_idx;
                        req_is_read   <= cpu_read;
                        req_is_write  <= cpu_write;
                        req_wdata     <= cpu_wdata;

                        state         <= S_LOOKUP;
                    end
                end

                // -----------------------------------------
                S_LOOKUP: begin
                    // Evaluamos hit/miss con la linea actual
                    if (hit_req) begin
                        // ===== HIT =====
                        last_hit <= 1'b1;

                        if (req_is_read) begin
                            // Lectura desde el bloque
                            cpu_rdata <= get_word(data_array[req_index], req_word_idx);
                            cpu_ready <= 1'b1;
                            state     <= S_IDLE;
                        end else if (req_is_write) begin
                            // Escritura en la linea y marcar dirty
                            data_array[req_index]  <= set_word(data_array[req_index],
                                                               req_word_idx,
                                                               req_wdata);
                            dirty_array[req_index] <= 1'b1;
                            cpu_ready              <= 1'b1;
                            state                  <= S_IDLE;
                        end
                    end else begin
                        // ===== MISS =====
                        last_hit <= 1'b0;

                        // Guardamos tag de la victima para write-back si fuera necesario
                        victim_tag <= line_tag;

                        // ¿Hay que escribir de vuelta?
                        if (line_valid && line_dirty) begin
                            // Preparar write-back
                            mem_addr_reg  <= {line_tag, req_index, {OFFSET_BITS{1'b0}}};
                            mem_wdata_reg <= data_array[req_index];
                            mem_do_read   <= 1'b0;
                            mem_do_write  <= 1'b1;
                            mem_req_sent  <= 1'b0;
                            state         <= S_WRITEBACK;
                        end else begin
                            // Ir directo a leer el nuevo bloque
                            mem_addr_reg  <= {req_tag, req_index, {OFFSET_BITS{1'b0}}};
                            mem_do_read   <= 1'b1;
                            mem_do_write  <= 1'b0;
                            mem_req_sent  <= 1'b0;
                            state         <= S_MEM_READ;
                        end
                    end
                end

                // -----------------------------------------
                S_WRITEBACK: begin
                    // En este estado esperamos a que memoria termine el write-back
                    if (!mem_req_sent) begin
                        // Acabamos de emitir la peticiÃ³n (pulso de 1 ciclo)
                        mem_req_sent <= 1'b1;
                    end else if (mem_ready) begin
                        // Write-back completado â†’ ahora pedimos el nuevo bloque
                        mem_req_sent <= 1'b0;
                        mem_do_write <= 1'b0;
                        mem_do_read  <= 1'b1;
                        mem_addr_reg <= {req_tag, req_index, {OFFSET_BITS{1'b0}}};
                        state        <= S_MEM_READ;
                    end
                end

                // -----------------------------------------
                S_MEM_READ: begin
                    // Esperamos a que memoria entregue el bloque
                    if (!mem_req_sent) begin
                        // Emitimos peticion de lectura (pulso)
                        mem_req_sent <= 1'b1;
                    end else if (mem_ready) begin
                        mem_req_sent <= 1'b0;
                        mem_do_read  <= 1'b0;

                        // Llenamos la linea con el nuevo bloque
                        if (req_is_write) begin
                            // Caso write-allocate: modificamos la palabra y marcamos dirty
                            automatic logic [BLOCK_BYTES*8-1:0] new_block;
                            new_block = set_word(mem_rdata_block, req_word_idx, req_wdata);
                            data_array[req_index]  <= new_block;
                            dirty_array[req_index] <= 1'b1;
                        end else begin
                            data_array[req_index]  <= mem_rdata_block;
                            dirty_array[req_index] <= 1'b0;
                        end

                        tag_array[req_index]   <= req_tag;
                        valid_array[req_index] <= 1'b1;

                        // Ahora respondemos a la CPU
                        if (req_is_read) begin
                            cpu_rdata <= get_word(
                                (req_is_write ? // este caso no se da, solo para seguridad
                                 set_word(mem_rdata_block, req_word_idx, req_wdata) :
                                 mem_rdata_block),
                                req_word_idx
                            );
                        end

                        cpu_ready <= 1'b1;
                        state     <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // Salida de hit/miss de la ultima operacion completada
    always_comb begin
        cpu_hit = last_hit;
    end

endmodule
