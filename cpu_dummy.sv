module cpu_dummy #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst,

    // Interfaz hacia la cache
    output logic [ADDR_WIDTH-1:0]  cpu_addr,
    output logic [DATA_WIDTH-1:0]  cpu_wdata,
    output logic                   cpu_read,
    output logic                   cpu_write,
    input  logic [DATA_WIDTH-1:0]  cpu_rdata,
    input  logic                   cpu_ready,
    input  logic                   cpu_hit      // hit/miss de la cache
);

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_REQ,
        ST_WAIT,
        ST_DONE
    } cpu_state_t;

    cpu_state_t state;

    // indice de operacion
    int op_idx;

    // Numero total de operaciones en la secuencia
    localparam int N_OPS = 6;

    // Señales deseadas para la operacion actual
    logic [ADDR_WIDTH-1:0]  op_addr;
    logic [DATA_WIDTH-1:0]  op_wdata;
    logic                   op_is_read;
    logic                   op_is_write;

    // Definicion de la secuencia de operaciones
    always_comb begin
        // Defaults
        op_addr     = '0;
        op_wdata    = '0;
        op_is_read  = 1'b0;
        op_is_write = 1'b0;

        case (op_idx)
            0: begin
                // Read 0x0000
                op_addr     = 16'h0000;
                op_is_read  = 1'b1;
            end
            1: begin
                // Read 0x0004 (mismo bloque que 0x0000)
                op_addr     = 16'h0004;
                op_is_read  = 1'b1;
            end
            2: begin
                // Write 0x0008 (misma lÃ­nea, se vuelve dirty)
                op_addr      = 16'h0008;
                op_is_write  = 1'b1;
                op_wdata     = 32'h1111_1111;
            end
            3: begin
                // Read 0x0400 (mismo indice, tag distinto al reemplazo)
                op_addr     = 16'h0400;
                op_is_read  = 1'b1;
            end
            4: begin
                // Read 0x0000 otra vez (ahora es miss, la linea fue reemplazada)
                op_addr     = 16'h0000;
                op_is_read  = 1'b1;
            end
            5: begin
                // Read 0x0400 (hit esperado)
                op_addr     = 16'h0400;
                op_is_read  = 1'b1;
            end
            default: begin
                op_addr     = '0;
                op_is_read  = 1'b0;
                op_is_write = 1'b0;
            end
        endcase
    end

    // FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= ST_IDLE;
            op_idx    <= 0;
            cpu_addr  <= '0;
            cpu_wdata <= '0;
            cpu_read  <= 1'b0;
            cpu_write <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    cpu_read  <= 1'b0;
                    cpu_write <= 1'b0;
                    if (op_idx < N_OPS) begin
                        state <= ST_REQ;
                    end else begin
                        state <= ST_DONE;
                    end
                end

                ST_REQ: begin
                    // Emitimos la solicitud
                    cpu_addr  <= op_addr;
                    cpu_wdata <= op_wdata;
                    cpu_read  <= op_is_read;
                    cpu_write <= op_is_write;

                    state <= ST_WAIT;
                end

                ST_WAIT: begin
                    // Quitamos las señales de control, esperamos cpu_ready
                    cpu_read  <= 1'b0;
                    cpu_write <= 1'b0;

                    if (cpu_ready) begin
                        // Log en consola
                        $display("[%0t] CPU op %0d: %s addr=0x%04h, rdata=0x%08h, hit=%0d",
                                 $time,
                                 op_idx,
                                 (op_is_read ? "READ " : "WRITE"),
                                 op_addr,
                                 cpu_rdata,
                                 cpu_hit);
                        op_idx <= op_idx + 1;
                        state  <= ST_IDLE;
                    end
                end

                ST_DONE: begin
                    cpu_read  <= 1'b0;
                    cpu_write <= 1'b0;
                    // Nada mas, el testbench cortara¡ la simulacion
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
