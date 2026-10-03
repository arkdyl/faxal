/* debug.c: bytecode disassembler (faxal --dump) */
#include "faxal.h"

static const char* NAMES[] = {
  [OP_CONSTANT] = "CONSTANT", [OP_NIL] = "NIL", [OP_TRUE] = "TRUE", [OP_FALSE] = "FALSE", [OP_POP] = "POP",
  [OP_DUP] = "DUP", [OP_DUP2] = "DUP2", [OP_GET_LOCAL] = "GET_LOCAL", [OP_SET_LOCAL] = "SET_LOCAL",
  [OP_GET_GLOBAL] = "GET_GLOBAL", [OP_DEFINE_GLOBAL] = "DEFINE_GLOBAL", [OP_SET_GLOBAL] = "SET_GLOBAL",
  [OP_GET_UPVALUE] = "GET_UPVALUE", [OP_SET_UPVALUE] = "SET_UPVALUE", [OP_GET_PROPERTY] = "GET_PROPERTY",
  [OP_SET_PROPERTY] = "SET_PROPERTY", [OP_GET_INDEX] = "GET_INDEX", [OP_SET_INDEX] = "SET_INDEX", [OP_SLICE] = "SLICE",
  [OP_EQUAL] = "EQUAL", [OP_GREATER] = "GREATER", [OP_LESS] = "LESS", [OP_ADD] = "ADD", [OP_SUB] = "SUB",
  [OP_MUL] = "MUL", [OP_DIV] = "DIV", [OP_MOD] = "MOD", [OP_POW] = "POW", [OP_NEG] = "NEG", [OP_NOT] = "NOT",
  [OP_IN] = "IN", [OP_RANGE] = "RANGE", [OP_JUMP] = "JUMP", [OP_JUMP_IF_FALSE] = "JUMP_IF_FALSE", [OP_LOOP] = "LOOP",
  [OP_CALL] = "CALL", [OP_INVOKE] = "INVOKE", [OP_CLOSURE] = "CLOSURE", [OP_CLOSE_UPVALUE] = "CLOSE_UPVALUE",
  [OP_RETURN] = "RETURN", [OP_BUILD_LIST] = "BUILD_LIST", [OP_BUILD_MAP] = "BUILD_MAP", [OP_FOR_NEXT] = "FOR_NEXT",
  [OP_SWAP] = "SWAP", [OP_BY] = "BY", [OP_JUMP_IF_NIL] = "JUMP_IF_NIL", [OP_JUMP_IF_NOT_NIL] = "JUMP_IF_NOT_NIL",
  [OP_CLASS] = "CLASS", [OP_INHERIT] = "INHERIT", [OP_METHOD] = "METHOD", [OP_GET_SUPER] = "GET_SUPER", [OP_SUPER_INVOKE] = "SUPER_INVOKE",
  [OP_TRY] = "TRY", [OP_END_TRY] = "END_TRY", [OP_THROW] = "THROW", [OP_IMPORT] = "IMPORT", [OP_REPL_PRINT] = "REPL_PRINT",
};

static void printConst(Chunk* c, int idx) {
  Buffer b; bufInit(&b);
  vm.noToStr = true;
  appendValue(&b, c->constants.values[idx], true, 0);
  vm.noToStr = false;
  fputs(" '", stdout);
  if (b.data) fwrite(b.data, 1, (size_t)b.len, stdout);   /* by length: a string may contain a NUL byte */
  fputc('\'', stdout);
  bufFree(&b);
}

static int disassembleInstruction(Chunk* c, int offset) {
  printf("%04d ", offset);
  if (offset > 0 && c->lines[offset] == c->lines[offset - 1]) printf("   | ");
  else printf("%4d ", c->lines[offset]);
  uint8_t op = c->code[offset];
  const char* name = op < sizeof NAMES / sizeof NAMES[0] && NAMES[op] ? NAMES[op] : "???";
  printf("%-16s", name);
  switch (op) {
    case OP_CLASS: case OP_METHOD: case OP_GET_SUPER:
    case OP_CONSTANT: case OP_GET_GLOBAL: case OP_DEFINE_GLOBAL: case OP_SET_GLOBAL: case OP_GET_PROPERTY: case OP_SET_PROPERTY: {
      int idx = (c->code[offset + 1] << 8) | c->code[offset + 2];
      printf(" %4d", idx); printConst(c, idx); printf("\n");
      return offset + 3;
    }
    case OP_GET_LOCAL: case OP_SET_LOCAL: case OP_GET_UPVALUE: case OP_SET_UPVALUE: case OP_CALL:
      printf(" %4d\n", c->code[offset + 1]);
      return offset + 2;
    case OP_JUMP: case OP_JUMP_IF_FALSE: case OP_TRY: case OP_JUMP_IF_NIL: case OP_JUMP_IF_NOT_NIL: {
      int j = (c->code[offset + 1] << 8) | c->code[offset + 2];
      printf(" %4d -> %d\n", offset, offset + 3 + j);
      return offset + 3;
    }
    case OP_LOOP: {
      int j = (c->code[offset + 1] << 8) | c->code[offset + 2];
      printf(" %4d -> %d\n", offset, offset + 3 - j);
      return offset + 3;
    }
    case OP_INVOKE: case OP_SUPER_INVOKE: {
      int idx = (c->code[offset + 1] << 8) | c->code[offset + 2];
      printf(" (%d args)", c->code[offset + 3]); printConst(c, idx); printf("\n");
      return offset + 4;
    }
    case OP_BUILD_LIST: case OP_BUILD_MAP:
      printf(" %4d\n", (c->code[offset + 1] << 8) | c->code[offset + 2]);
      return offset + 3;
    case OP_FOR_NEXT: {
      int j = (c->code[offset + 2] << 8) | c->code[offset + 3];
      printf(" slot %d, exit -> %d\n", c->code[offset + 1], offset + 4 + j);
      return offset + 4;
    }
    case OP_CLOSURE: {
      int idx = (c->code[offset + 1] << 8) | c->code[offset + 2];
      printf(" %4d", idx); printConst(c, idx); printf("\n");
      ObjFunction* f = AS_FUNCTION(c->constants.values[idx]);
      int o = offset + 3;
      for (int i = 0; i < f->upvalueCount; i++) {
        printf("%04d    |                   %s %d\n", o, c->code[o] ? "local" : "upvalue", c->code[o + 1]);
        o += 2;
      }
      return o;
    }
    default:
      printf("\n");
      return offset + 1;
  }
}

void disassembleFunction(ObjFunction* f) {
  printf("== %s ==\n", f->name ? f->name->chars : f->isScript ? "<script>" : "<lambda>");
  for (int off = 0; off < f->chunk.count;) off = disassembleInstruction(&f->chunk, off);
  printf("\n");
}
