#include <stdio.h>
int main() {
    int c = 'A';
    int i;
    puts("puts works");
    for (i = 0; i < 5; i++) {
        printf("%c", c + i);
    }
    printf("\n");
    printf("%x %x %d\n", 3054, 48879, '\n');
    printf("100%%\n");
    putchar('o'); putchar('k'); putchar('\n');
    i = 0;
    return 0;
}
