# frozen_string_literal: true

class Numeric
  def hex
    "0x#{to_s(16)}"
  end
end

class Memory
  MAX = 1024 * 64

  def reset
    @data = [0] * MAX
  end

  # Reads the byte at `address`.
  def [](address)
    @data[address]
  end

  # Writes the byte at `address`.
  def []=(address, value)
    @data[address] = value
  end

  def to_s(columns=16)
    (0...MAX).step(columns).map do |row_start|
      row = @data.slice(row_start, columns)

      row_start_address_str = "0x#{row_start.to_s(16).rjust(8, '0')}"
      hex_row = row.map { |byte| byte.to_s(16).rjust(2, "0") }.join(" ")
      ascii_row = row.map { |byte| byte >= 32 && byte <= 126 ? byte.chr : "." }.join

      "#{row_start_address_str} | #{hex_row} | #{ascii_row}"
    end.join("\n")
  end
end

class CPU
  INS = {
    LDA_IMMEDIATE: 0xa9,
    LDA_ZERO_PAGE: 0xa5,
    LDA_ZERO_PAGE_X: 0xb5,
    JSR: 0x20,
  }.freeze

  def initialize(memory)
    @memory = memory
    reset
  end

  def reset
    # Program counter
    @pc = 0xfffc
    # Stack pointer
    @sp = 0x0100
    # Registers: accumulator, x, and y
    @ra = @rx = @ry = 0

    @flags = {
      # Carry flag
      #   Set if the last operation caused an overflow from bit 7 of the result,
      #   or an underflow from bit 0. This flag is set during arithmetic,
      #   comparison, and logical shifts. It is explicitly set using the SEC
      #   instruction and cleared with the CLC instruction.
      c: false,
      # Zero flag
      #   Set if the result of the last operation was zero.
      z: false,
      # Interrupt disable flag
      #   Set if the program has executed a SEI instruction. While set, the
      #   processor won't respond to interrupts from devices. Cleared with
      #   the CLI instruction.
      i: false,
      # Decimal mode flag
      #   While set, the processor will use binary coded decimal arithmetic
      #   during addition and subtraction. It is explicitly set with the SED
      #   instruction and cleared with the CLD instruction.
      d: false,
      # Break command flag
      #   Set when a BRK instruction has been executed and an interrupt has been
      #   generated to process it.
      b: false,
      # Overflow flag
      #   Set during arithmetic operations if the result has yielded an invalid
      #   2's compliment result (adding to positive numbers and ending up with a
      #   negative result e.g. 64 + 64 => -128). It is determined by looking at
      #   the carry between bits 6 and 7 and between bit 7 and the carry flag.
      v: false,
      # Negative flag
      #   Set if the result of the last operation had bit 7 set to a one.
      n: false,
    }

    @memory.reset
  end

  def to_s
    <<~EOS
      Program counter: #{@pc.hex}
      Stack pointer: #{@sp.hex}
      Registers:
        A: #{@ra.hex}
        X: #{@rx.hex}
        Y: #{@ry.hex}
      Flags:
      #{@flags.map { |k, v| "  #{k.upcase}: #{v}" }.join("\n")}
    EOS
  end

  def read_byte(address)
    @clock -= 1
    @memory[address]
  end

  def fetch_byte
    address = @pc

    @pc += 1
    @clock -= 1

    @memory[address]
  end

  def fetch_word
    # Little endian
    data = @memory[@pc]
    @pc += 1
    data |= @memory[@pc] << 8
    @pc += 1

    @clock -= 2

    data
  end

  def write_word(address, value)
    # Little endian
    @memory[address] = value & 0xff
    @memory[address + 1] = value >> 8

    @clock -= 2
  end

  def add_byte(x, y)
    @clock -= 1
    # 0xff + 0x1 overflows to 0x0
    (x + y) % 0x100
  end

  def sub_word(x, y)
    @clock -= 1
    # 0x0 - 0x1 overflows to 0xffff
    (x - y) % 0x10000
  end

  def lda_set_flags
    @flags[:z] = @ra == 0
    @flags[:n] = (@ra & 0b10000000) > 0
  end

  def execute(cycles)
    @clock = cycles
    while @clock > 0
      instruction = fetch_byte
      case instruction
      when INS[:LDA_IMMEDIATE]
        @ra = fetch_byte
        lda_set_flags
      when INS[:LDA_ZERO_PAGE]
        zero_page_address = fetch_byte
        @ra = read_byte(zero_page_address)
        lda_set_flags
      when INS[:LDA_ZERO_PAGE_X]
        zero_page_address = add_byte(fetch_byte, @rx)
        @ra = read_byte(zero_page_address)
        lda_set_flags
      when INS[:JSR]
        jump_address = fetch_word
        write_word(@sp, @pc - 1)
        @sp += 2

        @pc = jump_address
        @clock -= 1
      else
        puts "Error: Instruction not found: #{instruction}"
      end
    end
  end
end

memory = Memory.new
cpu = CPU.new(memory)

memory[0xfffc] = CPU::INS[:JSR]
memory[0xfffd] = 0x42
memory[0xfffe] = 0x69

memory[0x6942] = CPU::INS[:LDA_IMMEDIATE]
memory[0x6943] = 0x69

cpu.execute(8)

puts memory
puts
puts cpu
