#include <stdio.h>
/* recursion with several arguments and a global counter */
int moves = 0;

void hanoi(int n, int from, int to, int via) {
    if (n == 0) return;
    hanoi(n - 1, from, via, to);
    moves++;
    if (n == 3) printf("move disk %d from %d to %d\n", n, from, to);
    hanoi(n - 1, via, to, from);
}

int gcd(int a, int b) {
    while (b != 0) {
        int t = a % b;
        a = b;
        b = t;
    }
    return a;
}

int main() {
    hanoi(5, 1, 3, 2);
    printf("moves=%d\n", moves);
    printf("gcd=%d neg=%d\n", gcd(1071, 462), -17 / 5);
    printf("%d %d\n", -17 % 5, 17 / -5);
    return 0;
}
