#include <stdio.h>
/* A medium-sized program: several functions, arrays, loops and precedence */

int scores[8] = {72, 95, 58, 88, 61, 99, 74, 80};
int grades[8];

int grade_of(int s) {
    if (s >= 90) return 4;
    else if (s >= 80) return 3;
    else if (s >= 70) return 2;
    return 1;
}

int sum(int n) {
    int i, total = 0;
    for (i = 1; i <= n; i++) total += i;
    return total;
}

int is_prime(int n) {
    int d;
    if (n < 2) return 0;
    for (d = 2; d * d <= n; d++) {
        if (n % d == 0) return 0;
    }
    return 1;
}

int power(int b, int e) {
    int r = 1;
    while (e > 0) {
        if (e & 1) r = r * b;
        b = b * b;
        e = e >> 1;
    }
    return r;
}

int main() {
    int i, best = -1, count = 0, collatz = 27, steps = 0;

    printf("precedence: %d %d %d\n", 2 + 3 * 4, 1 << 2 + 1, (2 + 3) * 4);
    printf("ternary: %d %d\n", 5 > 3 ? 10 : 20, 0 ? 1 : 2 ? 3 : 4);

    for (i = 0; i < 8; i++) {
        grades[i] = grade_of(scores[i]);
        if (scores[i] > best) best = scores[i];
    }
    printf("best score: %d\n", best);
    for (i = 0; i < 8; i++) printf("%d:%d ", scores[i], grades[i]);
    printf("\n");

    printf("sum(100)=%d power=%d\n", sum(100), power(3, 7));

    for (i = 1; i <= 30; i++) {
        if (!is_prime(i)) continue;
        count++;
        if (count > 6) break;
        printf("prime %d\n", i);
    }

    while (collatz != 1) {
        if (collatz % 2 == 0) collatz /= 2;
        else collatz = 3 * collatz + 1;
        steps++;
    }
    printf("collatz(27) steps=%d\n", steps);

    for (i = 0, count = 0; i < 20; i++) {
        count += i % 3 == 0 ? i : 0;
    }
    printf("multiples of 3 sum=%d\n", count);
    printf("negative: %d %d\n", -(3 + 4), -sum(4));
    return 0;
}
