class AppError {
  fn init(msg) { self.msg = msg }
  fn to_str() { return "AppError: " + self.msg }
}
fn run() { throw AppError("disk full") }
run()
# error: AppError: disk full
# error: at run (
