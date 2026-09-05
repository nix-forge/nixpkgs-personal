#include <stddef.h>

extern int cef_initialize(const void *, const void *, void *, void *);

int main(void)
{
    return cef_initialize(NULL, NULL, NULL, NULL) == 0 ? 1 : 0;
}
