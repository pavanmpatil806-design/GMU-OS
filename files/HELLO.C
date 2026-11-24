// first C program on GMU OS
#include <stdio.h>

int square(int x) { return x * x; }

int main() {
    int i;
    printf("Hello from C on GMU OS!\n");
    for (i = 1; i <= 5; i++) {
        printf("%d squared is %d\n", i, square(i));
    }
    return 0;
}
