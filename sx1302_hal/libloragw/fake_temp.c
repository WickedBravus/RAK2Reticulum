#include <stddef.h>

int stts751_configure(void) { 
    return 0; 
}

int stts751_get_temperature(float * temp) { 
    if (temp == NULL || (unsigned long)temp < 0x1000) {
        return -1; 
    }
    *temp = 30.0; 
    return 0; 
}
