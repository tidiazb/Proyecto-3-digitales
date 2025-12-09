`timescale 1ns/1ps

module tb_cache_top;

    // Señales de reloj y reset
    logic clk;
    logic rst;

    // Generacion de clock (100 MHz)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // periodo 10 ns
    end

    // Reset sincrono al inicio
    initial begin
        rst = 1'b1;
        #20;
        rst = 1'b0;
    end

    // DUT
    cache_top dut (
        .clk (clk),
        .rst (rst)
    );

    // =====================================================
    // Scoreboard
    // =====================================================

    localparam int N_OPS = 6;

    //  operaciones son lectura
    bit          exp_is_read [0:N_OPS-1];
    // Hit/miss esperado
    bit          exp_hit     [0:N_OPS-1];
    // Dato esperado en lecturas
    logic [31:0] exp_rdata   [0:N_OPS-1];

    // indice de operacion visto por el testbench
    int tb_op_idx;
    int errors;
    int checks;

    // Inicializacion de EXPECTATIVAS (solo arrays, NO tb_op_idx/errores aqui)
    initial begin
        integer i;
        for (i = 0; i < N_OPS; i++) begin
            exp_is_read[i] = 1'b0;
            exp_hit[i]     = 1'b0;
            exp_rdata[i]   = 32'hDEAD_BEEF;
        end

        // op 0: READ 0x0000 ? miss, 0x10000000
        exp_is_read[0] = 1'b1;
        exp_hit[0]     = 1'b0;
        exp_rdata[0]   = 32'h1000_0000;

        // op 1: READ 0x0004 ? hit, 0x10000000
        exp_is_read[1] = 1'b1;
        exp_hit[1]     = 1'b1;
        exp_rdata[1]   = 32'h1000_0000;

        // op 2: WRITE 0x0008 ? hit, no chequeo de dato
        exp_is_read[2] = 1'b0;
        exp_hit[2]     = 1'b1;

        // op 3: READ 0x0400 ? miss, 0x10000020
        exp_is_read[3] = 1'b1;
        exp_hit[3]     = 1'b0;
        exp_rdata[3]   = 32'h1000_0020;

        // op 4: READ 0x0000 ? miss, 0x10000000
        exp_is_read[4] = 1'b1;
        exp_hit[4]     = 1'b0;
        exp_rdata[4]   = 32'h1000_0000;

        // op 5: READ 0x0400 ? miss, 0x10000020
        exp_is_read[5] = 1'b1;
        exp_hit[5]     = 1'b0;
        exp_rdata[5]   = 32'h1000_0020;
    end

    // =====================================================
    // Monitor de operaciones completadas
    // =====================================================

    // Acceso a señales internas del top
    wire [15:0] cpu_addr  = dut.cpu_addr;
    wire [31:0] cpu_rdata = dut.cpu_rdata;
    wire        cpu_ready = dut.cpu_ready;
    wire        cpu_hit   = dut.cpu_hit;

    // iNICO proceso que maneja tb_op_idx / errors / checks
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            tb_op_idx <= 0;
            errors    <= 0;
            checks    <= 0;
        end else begin
            if (cpu_ready) begin
                if (tb_op_idx >= N_OPS) begin
                    $display("[%0t] ERROR: se recibiï¿½ una operaciï¿½n extra (tb_op_idx=%0d)",
                             $time, tb_op_idx);
                    errors <= errors + 1;
                end else begin
                    bit          expected_hit;
                    bit          expected_is_read;
                    logic [31:0] expected_rdata;

                    expected_hit     = exp_hit[tb_op_idx];
                    expected_is_read = exp_is_read[tb_op_idx];
                    expected_rdata   = exp_rdata[tb_op_idx];

                    $display("[%0t] OP %0d completada: addr=0x%04h, hit=%0d, rdata=0x%08h",
                             $time, tb_op_idx, cpu_addr, cpu_hit, cpu_rdata);

                    // Verificar hit/miss
                    checks <= checks + 1;
                    if (cpu_hit !== expected_hit) begin
                        $display("  -> ERROR: hit esperado=%0d, obtenido=%0d",
                                 expected_hit, cpu_hit);
                        errors <= errors + 1;
                    end else begin
                        $display("  -> OK: hit/miss correcto (%0d)", cpu_hit);
                    end

                    // Verificar dato solo en lecturas
                    if (expected_is_read) begin
                        checks <= checks + 1;
                        if (cpu_rdata !== expected_rdata) begin
                            $display("  -> ERROR: dato esperado=0x%08h, obtenido=0x%08h",
                                     expected_rdata, cpu_rdata);
                            errors <= errors + 1;
                        end else begin
                            $display("  -> OK: dato de lectura correcto");
                        end
                    end else begin
                        $display("  -> Escritura: solo se verifica hit/miss");
                    end

                    tb_op_idx <= tb_op_idx + 1;
                end
            end
        end
    end

    // =====================================================
    // Finalizacion automatica de la simulacion
    // =====================================================

    initial begin
        // Opcional: dump de ondas por si quieres ver en GTKWave
        $dumpfile("cache_wave.vcd");
        $dumpvars(0, tb_cache_top);

        // Esperar a que termine la secuencia de operaciones
        wait (!rst);
        wait (tb_op_idx == N_OPS);

        // Dar unos ciclos extra por si apareciera un cpu_ready inesperado
        #100;

        $display("====================================================");
        $display("   RESUMEN TEST CACHE");
        $display("   Chequeos realizados : %0d", checks);
        $display("   Errores encontrados  : %0d", errors);
        if (errors == 0)
            $display("   RESULTADO: ** TEST PASSED ? **");
        else
            $display("   RESULTADO: ** TEST FAILED ? **");
        $display("====================================================");

        $finish;
    end

endmodule
