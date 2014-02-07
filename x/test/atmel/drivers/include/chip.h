#ifndef _LIB_SAM3S_
#define _LIB_SAM3S_

/*
 * Peripherals registers definitions
 */
#if defined sam3s4
#elif defined sam3s2
#elif defined sam3s1
#else
    #warning Library does not support the specified chip, specifying sam3s4.
    #define sam3s4
#endif
#include "SAM3S.h"


/* Define attribute */
#if defined   ( __CC_ARM   ) /* Keil �Vision 4 */
    #define WEAK __attribute__ ((weak))
#elif defined ( __ICCARM__ ) /* IAR Ewarm 5.41+ */
    #define WEAK __weak
#elif defined (  __GNUC__  ) /* GCC CS3 2009q3-68 */
    #define WEAK __attribute__ ((weak))
#endif

/* Define NO_INIT attribute */
#if defined   ( __CC_ARM   )
    #define NO_INIT
#elif defined ( __ICCARM__ )
    #define NO_INIT __no_init
#elif defined (  __GNUC__  )
    #define NO_INIT
#endif


/*
 * Core
 */

#include "exceptions.h"

/*
 * Peripherals
 */
#include "pio.h"
//#include "pio_it.h"
#include "pmc.h"
//#include "spi.h"
#include "twi.h"
#include "trace.h"
//#include "wdt.h"

#endif /* _LIB_SAM3S_ */
