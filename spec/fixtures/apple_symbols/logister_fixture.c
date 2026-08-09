__attribute__((noinline)) int logister_fixture_target(int value) {
  return value + 42;
}

int main(void) {
  return logister_fixture_target(0);
}
