#include <stdio.h>
int main() {
    int a[6];
    int i, j, t;
    a[0] = 5; a[1] = 2; a[2] = 9; a[3] = 1; a[4] = 7; a[5] = 3;
    for (i = 0; i < 6; i++)
        for (j = 0; j < 5 - i; j++)
            if (a[j] > a[j + 1]) {
                t = a[j];
                a[j] = a[j + 1];
                a[j + 1] = t;
            }
    for (i = 0; i < 6; i++) printf("%d ", a[i]);
    printf("\n");
    return 0;
}
