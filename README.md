# 🧠 **Proyecto: Jerarquía de Memoria con Caché Direct-Mapped (Write-Back)**
### *Simulación en SystemVerilog – CPU Dummy · Data Cache · Main Memory · Testbench Autoverificable*

---

## 📌 **Descripción general**

Este proyecto implementa una **jerarquía de memoria completa** utilizando SystemVerilog.  
Incluye:

- una **caché direct-mapped** de 1 KiB,
- política **write-back** y **write-allocate**,
- bloques de **32 bytes**,
- una memoria principal de **64 KiB**,
- un CPU de prueba (*cpu_dummy*),
- y un **testbench autoverificable** que confirma el correcto funcionamiento del sistema.

El objetivo educativo es comprender:

- organización de caché,  
- detección de *hits* y *misses*,  
- reemplazo y manejo de líneas sucias (*dirty*),  
- interacción CPU ↔ Caché ↔ Memoria,  
- verificación automática mediante scoreboards.

---

## 🧩 **Arquitectura del sistema**

```
             +-----------------+
             |    CPU Dummy    |
             | (genera accesos)|
             +--------+--------+
                      |
                      | addr, r/w, data
                      v
             +--------+--------+
             |    Data Cache   |
             | Direct-Mapped   |
             | Write-Back/W-A  |
             +--------+--------+
                      |
                      | bloques 256 bits
                      v
             +--------+--------+
             |  Main Memory    |
             |     64 KiB      |
             |  Latencia 2c    |
             +-----------------+
```

---

## 📁 **Estructura del repositorio**

```
├── cpu_dummy.sv
├── data_cache.sv
├── main_memory.sv
├── cache_top.sv
├── tb_cache_top.sv
└── README.md   (este archivo)
```

---

## 🔹 **1. Módulo `data_cache.sv` — Caché Direct-Mapped**

Implementa:

- 32 líneas de caché  
- tamaño total: 1024 bytes  
- bloques: 32B (256 bits)  
- *write-back*  
- *write-allocate*  
- manejo de `valid`, `dirty` y `tag`

### ✔ Características clave

- Divide la dirección en **tag / índice / offset**.
- En *hit*:
  - lectura directa del bloque,
  - escritura de palabra y marcado de línea sucia.
- En *miss*:
  - si la línea víctima está dirty → write-back,
  - realiza fetch del nuevo bloque desde memoria,
  - actualiza `tag`, `valid`, `dirty`.

### ✔ FSM interna

```
S_IDLE
   ↓
S_LOOKUP  ←──────────────┐
   ↓ (miss sucia)         │
S_WRITEBACK               │
   ↓                      │
S_MEM_READ ───────────────┘
```

---

## 🔹 **2. Módulo `main_memory.sv` — Memoria de 64 KiB**

- Memoria modelada para simulación.
- Acceso **por bloques de 256 bits**.
- Latencia configurable (2 ciclos).
- Inicialización con patrón reconocible para debugging.

### ✔ Flujo interno

```
Nueva operación →
    latchea parámetros →
        espera latencia →
            ejecuta read/write →
                mem_ready = 1
```

---

## 🔹 **3. Módulo `cpu_dummy.sv` — Generador de accesos**

Simula un mini procesador produciendo **una secuencia diseñada para probar la caché**.

### ✔ Secuencia de operaciones

| Op | Dirección | Tipo | Resultado Esperado |
|----|-----------|------|--------------------|
| 0 | 0x0000 | Read | Miss |
| 1 | 0x0004 | Read | Hit |
| 2 | 0x0008 | Write | Hit (dirty=1) |
| 3 | 0x0400 | Read | Miss + Write-back |
| 4 | 0x0000 | Read | Miss |
| 5 | 0x0400 | Read | Miss |

### ✔ FSM del CPU dummy

```
ST_IDLE → ST_REQ → ST_WAIT → ST_IDLE → ... → ST_DONE
```

---

## 🔹 **4. Módulo `cache_top.sv` — Integración del sistema**

Une:

- `cpu_dummy`  
- `data_cache`  
- `main_memory`

Actúa como **DUT** para la verificación.

---

## 🔹 **5. Testbench `tb_cache_top.sv` — Scoreboard autoverificable**

Implementa:

- reloj y reset,
- instancia del DUT,
- **scoreboard** con resultados esperados de cada operación,
- comparación automática entre resultados reales y esperados,
- informe final en consola.

### ✔ Ejemplo de salida

```
====================================================
   RESUMEN TEST CACHE
   Chequeos realizados : 6
   Errores encontrados  : 0
   RESULTADO: ** TEST PASSED ✅ **
====================================================
```

---

## ▶️ **Cómo ejecutar la simulación**

### Requisitos

- Icarus Verilog  
- Verilator  
- Vivado Simulator  
- EDA Playground  

### Comando típico

```sh
iverilog -g2012 -o cache_sim   cpu_dummy.sv data_cache.sv main_memory.sv cache_top.sv tb_cache_top.sv

vvp cache_sim
```

### Ver ondas

```sh
gtkwave cache_wave.vcd
```

---

## 📚 **Conceptos demostrados**

- Organización y funcionamiento de una **caché direct-mapped**.  
- Manejo completo de *hits* y *misses*.  
- Ciclo write-back y write-allocate.  
- Comunicación bloque-a-bloque entre caché y memoria.  
- Verificación automática con *scoreboard*.  
- Diseño modular en SystemVerilog.

---

## 🏁 **Estado del proyecto**

✔ Simulación funcional  
✔ Testbench autoverificable  
✔ Jerarquía CPU–Cache–Memoria verificada  
✔ Resultados correctos  

---

