#include <stdio.h>
int main() {
    int n = 0, x = 7;
    while (1) {
        n++;
        if (n % 2 == 0) continue;
        if (n > 9) break;
        printf("%d ", n);
    }
    printf("\n");
    printf("%d %d %d\n", x & 3, x | 8, x ^ 5);
    printf("%d %d\n", x << 2, -x >> 1);
    printf("%s\n", x > 5 ? "big" : "small");
    printf("[%5d][%x]\n", 42, 255);
    return 0;
}
