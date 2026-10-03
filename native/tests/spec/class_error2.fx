class A { fn f() { return super.f() } }
# compile-error: 'super' can only be used in a class that extends
