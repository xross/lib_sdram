// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <platform.h>
#include <print.h>
#include "sdram.h"

 /*
  * Put an SDRAM slice into 'square' slot of A16 slice kit, or into slot '2' of the xCore200 slice kit
  * For xCORE200 slice kit, ensure Link switch on debug adapter is switched to "off" to avoid contention
  */

#define SDRAM_256Mb   0 //Use IS45S16160D 256Mb, othewise default IS42S16400D 64Mb used on SDRAM slice

#define CAS_LATENCY   2
#define REFRESH_MS    64
#define CLOCK_DIV     4 //Note clock div 4 gives (500/ (4*2)) = 62.5MHz
#define DATA_BITS     16

#if SDRAM_256Mb
#define REFRESH_CYCLES 8192
#define COL_ADDRESS_BITS 9
#define ROW_ADDRESS_BITS 13
#define BANK_ADDRESS_BITS 2
#define BANK_COUNT    4
#define ROW_COUNT     8192
#define ROW_WORDS     256
#else
#define REFRESH_CYCLES 4096
#define COL_ADDRESS_BITS 8
#define ROW_ADDRESS_BITS 12
#define BANK_ADDRESS_BITS 2
#define BANK_COUNT    4
#define ROW_COUNT     4096
#define ROW_WORDS     128
#endif
#pragma unsafe arrays
void application(streaming chanend c_server, s_sdram_state sdram_state) {
#define BUF_WORDS (240)

    unsigned buffer_0[ROW_WORDS];
    unsigned buffer_1[ROW_WORDS];
    unsigned buffer_2[ROW_WORDS];
    unsigned buffer_3[ROW_WORDS];

  unsigned * movable buffer_pointer_0 = buffer_0;
  unsigned * movable buffer_pointer_1 = buffer_1;
  unsigned * movable buffer_pointer_2 = buffer_2;
  unsigned * movable buffer_pointer_3 = buffer_3;

  timer t;
  unsigned time;
#define SECONDS 2
  unsigned words_since_timeout = 0;
  t :> time;
  sdram_read(c_server, sdram_state, 0, ROW_WORDS, move(buffer_pointer_0));
  sdram_read(c_server, sdram_state, 0, ROW_WORDS, move(buffer_pointer_1));
  sdram_read(c_server, sdram_state, 0, ROW_WORDS, move(buffer_pointer_2));
  sdram_read(c_server, sdram_state, 0, ROW_WORDS, move(buffer_pointer_3));
  while(1){
    select {
      case t when timerafter(time + SECONDS*100000000) :> time:
        printintln(words_since_timeout*4/SECONDS);
        words_since_timeout = 0;
        break;
      case sdram_complete(c_server, sdram_state, buffer_pointer_0):{
        words_since_timeout += ROW_WORDS;
        sdram_read(c_server, sdram_state, 0, ROW_WORDS, move(buffer_pointer_0));
        break;
      }
    }
  }
}

void sdram_client(streaming chanend c_server) {
  set_thread_fast_mode_on();
  s_sdram_state sdram_state;
  sdram_init_state(c_server, sdram_state);
  application(c_server, sdram_state);
}

#ifdef __XS2A__
//Slot 2 on xCORE200 slicekit
#define      SERVER_TILE            0
on tile[SERVER_TILE] : out buffered port:32   sdram_dq_ah                 = XS1_PORT_16B;
on tile[SERVER_TILE] : out buffered port:32   sdram_cas                   = XS1_PORT_1J;
on tile[SERVER_TILE] : out buffered port:32   sdram_ras                   = XS1_PORT_1I;
on tile[SERVER_TILE] : out buffered port:8    sdram_we                    = XS1_PORT_1K;
on tile[SERVER_TILE] : out port               sdram_clk                   = XS1_PORT_1L;
on tile[SERVER_TILE] : clock                  sdram_cb                    = XS1_CLKBLK_2;
#else
//Square slot on A16 slicekit
#define      SERVER_TILE            1
on tile[SERVER_TILE] : out buffered port:32   sdram_dq_ah                 = XS1_PORT_16A;
on tile[SERVER_TILE] : out buffered port:32   sdram_cas                   = XS1_PORT_1B;
on tile[SERVER_TILE] : out buffered port:32   sdram_ras                   = XS1_PORT_1G;
on tile[SERVER_TILE] : out buffered port:8    sdram_we                    = XS1_PORT_1C;
on tile[SERVER_TILE] : out port               sdram_clk                   = XS1_PORT_1F;
on tile[SERVER_TILE] : clock                  sdram_cb                    = XS1_CLKBLK_2;
#endif

int main() {
    streaming chan c_sdram[1];
  par {
        on tile[SERVER_TILE]:  sdram_client(c_sdram[0]);
        on tile[SERVER_TILE]:sdram_server(c_sdram, 1,
            sdram_dq_ah,
            sdram_cas,
            sdram_ras,
            sdram_we,
            sdram_clk,
            sdram_cb,
            CAS_LATENCY,
            ROW_WORDS,
            DATA_BITS,
            COL_ADDRESS_BITS,
            ROW_ADDRESS_BITS,
            BANK_ADDRESS_BITS,
            REFRESH_MS,
            REFRESH_CYCLES,
            CLOCK_DIV);
        on tile[0]: par(int i=0;i<6;i++) while(1);
  }
  return 0;
}
