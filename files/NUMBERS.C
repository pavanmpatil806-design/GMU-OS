#include <stdio.h>
/* recursion, loops and arrays */
int primes[50];

int fact(int n) {
    if (n <= 1) return 1;
    return n * fact(n - 1);
}

int fib(int n) {
    int a = 0, b = 1, t, i;
    for (i = 0; i < n; i++) {
        t = a + b;
        a = b;
        b = t;
    }
    return a;
}

int main() {
    int i, j, count = 0;
    for (i = 2; i < 50; i++) primes[i] = 1;
    for (i = 2; i < 50; i++) {
        if (primes[i]) {
            count++;
            printf("%d ", i);
            for (j = i * 2; j < 50; j += i) primes[j] = 0;
        }
    }
    printf("\ncount=%d\n", count);
    printf("fact(10)=%d fib(20)=%d\n", fact(10), fib(20));
    return 0;
}
