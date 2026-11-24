#include <stdio.h>
int total = 0;
int data[5] = {3, 1, 4, 1, 5};

void add(int v) {
    total += v;
}

int main() {
    int i;
    for (i = 0; i < 5; i++) add(data[i]);
    printf("total=%d\n", total);
    if (total > 10 && total < 20 || 0) printf("in range\n");
    if (!(total == 14)) printf("bad\n"); else printf("ok\n");
    return 0;
}
