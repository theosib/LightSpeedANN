#!/usr/bin/ruby


$use_sse = true
$double = false
#$use_ssex = false
$float = $double ? "double" : "float"
$wsize = $double ? 2 : 1
$quantize_fbits = 7
$quantize_ibits = 0

def quantize(len, ibits, fbits)
  x = ""
  x += "__attribute__((noinline)) static "
  x += "void quantize_#{len}_#{ibits}_#{fbits}(#{$float} *a) {\n"
  x += "    int i, j, neg;\n"
  x += "    #{$float} v;\n"
  x += "    for (i=0; i<#{len}; i++) {\n"
  x += "        v = *a;\n"
  x += "        neg = v < 0;\n"
  x += "        if (neg) v = -v;\n"
  x += "        j = v * #{(1<<fbits)} + 0.5;\n"
  x += "        if (j > #{(1<<(ibits+fbits))-1}) j = #{(1<<(ibits+fbits))-1};\n"
  #x += "        j &= #{(1<<(ibits+fbits))-1};\n"
  x += "        v = (#{$float})j * (#{$float})#{1.0 / (1<<fbits)};\n"
  x += "        if (neg) v = -v;\n"
  x += "        *a++ = v;\n"
  x += "    }\n}\n\n"
  x
end
  

def memclr(len)
  x = ""
  if (len > 8)
    x += "__attribute__((noinline)) "
  end
  x += "static void memory_clear_#{len}(#{$float} *dst) {\n"
  #x += "   memset(dst, 0, #{len}*sizeof(#{$float}));\n"
  
  i = 0
  
  if $use_sse
    len *= $wsize
    
    x += "    __m128 zero;\n"
    x += "    zero = _mm_setzero_ps();\n"
    while (len >= 4)
      x += "    _mm_store_ps((float *)dst + #{i}, zero);\n"
      i += 4
      len -= 4
    end
    if (len >= 2)
      x += "    _mm_store_sd((double *)((float *)dst + #{i}), (__m128d)zero);\n"
      i += 2
      len -= 2
    end
    if (len >= 1)
      x += "    _mm_store_ss((float *)dst + #{i}, zero);\n"
    end
  else
    while (len > 0) 
      x += "    dst[#{i}] = 0;\n"
      i += 1
      len -= 1
    end
  end      
  
  x + "}\n\n"
end


def memcpy(len)
  x = ""
  if (len > 8)
    x += "__attribute__((noinline)) "
  end
  x += "static void memory_copy_#{len}(#{$float} *dst, #{$float} *src) {\n"
  i = 0
    
  if $use_sse
    len *= $wsize
    len2 = len
    
    if (len >= 8)
      x += "    __m128 tmp;\n"
      x += "    if (((long)src) & 0xf) {\n"
      i = 0
      while (len >= 4)
        x += "        tmp = _mm_loadu_ps((float *)src + #{i});\n"
        x += "        _mm_store_ps((float *)dst + #{i}, tmp);\n"
        len -= 4
        i += 4
      end
      x += "    } else {\n"
      i = 0
      while (len2 >= 4)
        x += "        tmp = _mm_load_ps((float *)src + #{i});\n"
        x += "        _mm_store_ps((float *)dst + #{i}, tmp);\n"
        len2 -= 4
        i += 4
      end
      x += "    }\n"
    end
    
    if ($double)
      while (len > 0)
        x += "    dst[#{i/2}] = src[#{i/2}];\n"
        i += 2
        len -= 2
      end
    else
      while (len > 0)
        x += "    dst[#{i}] = src[#{i}];\n"
        i += 1
        len -= 1
      end
    end
  else
    while (len > 0) 
      x += "    dst[#{i}] = src[#{i}];\n"
      len -= 1
      i += 1
    end
  end
    
  x + "}\n\n"
end
        


def subtract(len)
  # Emit a function that subtracts b from a and writes to c
    
  x = ""
  if (len > 8)
    x += "__attribute__((noinline)) "
  end
  x += "static void subtract_#{len}(#{$float} *a, #{$float} *b, #{$float} *c) {\n"
  i = 0
  
  if $use_sse
    if $double
      if len >= 4
        x += "    __m128d ina, inb;\n"
        while (len >= 2)
          x += "    ina = _mm_load_pd(a + #{i});\n"
          x += "    inb = _mm_load_pd(b + #{i});\n"
          x += "    ina = _mm_sub_pd(ina, inb);\n"
          x += "    _mm_store_pd(c + #{i}, ina);\n"
          i += 2
          len -= 2
        end
      end
    else
      if len >= 4
        x += "    __m128 ina, inb;\n"
        while (len >= 4)
          x += "    ina = _mm_load_ps(a + #{i});\n"
          x += "    inb = _mm_load_ps(b + #{i});\n"
          x += "    ina = _mm_sub_ps(ina, inb);\n"
          x += "    _mm_store_ps(c + #{i}, ina);\n"
          i += 4
          len -= 4
        end
      end
    end
  end
      
  while (len > 0) 
    x += "    c[#{i}] = a[#{i}] - b[#{i}];\n"
    i += 1
    len -= 1
  end
    
  x + "}\n\n"
end

def subtract_sig(len)
  # Emit a function that subtracts b from a and writes to c
    
  x = ""
  if (len > 8)
    x += "__attribute__((noinline)) "
  end
  x += "static void subtract_sig_#{len}(#{$float} *a, #{$float} *b, #{$float} *c) {\n"
  if $double
    x += "    __m128d ina, inb, ones;\n"
  else
    x += "    __m128 ina, inb, ones;\n"
  end
  x += "    #{$float} bf;\n"
  
  i = 0
  
  if $use_sse && len >= 4
    if $double
      x += "    ones = _mm_set1_pd(1.0);\n"
      while (len >= 2) 
        x += "    ina = _mm_load_pd(a + #{i});\n"
        x += "    inb = _mm_load_pd(b + #{i});\n"
        x += "    ina = _mm_sub_pd(ina, inb);\n"
        x += "    inb = _mm_mul_pd(inb, inb);\n"    
        x += "    inb = _mm_sub_pd(ones, inb);\n"
        x += "    ina = _mm_mul_pd(inb, ina);\n"
        x += "    _mm_store_pd(c + #{i}, ina);\n"
        i += 2
        len -= 2
      end
    else
      x += "    ones = _mm_set1_ps(1.0f);\n"
      while (len >= 4)
        x += "    ina = _mm_load_ps(a + #{i});\n"
        x += "    inb = _mm_load_ps(b + #{i});\n"
        x += "    ina = _mm_sub_ps(ina, inb);\n"
        x += "    inb = _mm_mul_ps(inb, inb);\n"    
        x += "    inb = _mm_sub_ps(ones, inb);\n"
        x += "    ina = _mm_mul_ps(inb, ina);\n"
        x += "    _mm_store_ps(c + #{i}, ina);\n"
        i += 4
        len -= 4
      end
    end
  end

  while (len > 0) 
    x += "    bf = b[#{i}];\n"
    x += "    c[#{i}] = (a[#{i}] - bf) * (1 - bf*bf);\n"
    i += 1
    len -= 1
  end
    
  x + "}\n\n"
end


def dotprod(len)
  io = 0
  wo = 0
  hsum = false
  
  x = ""
  if (len > 8)
    x += "__attribute__((noinline)) "
  end
  x += "static #{$float} dotprod_#{len}(#{$float} *weights, #{$float} *values) {\n"
  
  if $use_sse && len >= 4
    x += "    #{$float} sum0, sum1, sum2, sum3;\n"
    if $double
      x += "    __m128d wei, inp, prod, total0, total1, total2, total3;\n"

      got = 1
      x += "    inp    = _mm_load_pd(values+#{io});\n"
      x += "    wei    = _mm_load_pd(weights+#{wo});\n"
      x += "    total0 = _mm_mul_pd(inp, wei);\n"
      len -= 2
      io += 2
      wo += 2

      while (len >= 2)
        x += "    inp   = _mm_load_pd(values+#{io});\n"
        x += "    wei   = _mm_load_pd(weights+#{wo});\n"
        
        if (0 != (got & (1<<(3&(io/2)))))
          x += "    prod  = _mm_mul_pd(inp, wei);\n"
          x += "    total#{3&(io/2)} = _mm_add_pd(prod, total#{3&(io/2)});\n"
        else
          x += "    total#{3&(io/2)} = _mm_mul_pd(inp, wei);\n"
          got |= 1<<(3&(io/2))
        end
        
        len -= 2
        io += 2
        wo += 2
      end
      
      case got
      when 3
        x += "    total0 = _mm_add_pd(total0, total1);\n"
      when 7
        x += "    total0 = _mm_add_pd(total0, total1);\n"
        x += "    total0 = _mm_add_pd(total0, total2);\n"
      when 15
        x += "    total0 = _mm_add_pd(total0, total1);\n"
        x += "    total2 = _mm_add_pd(total2, total3);\n"
        x += "    total0 = _mm_add_pd(total0, total2);\n"
      end

      x += "    total0 = _mm_hadd_pd(total0, total0);\n"
      x += "    _mm_store_sd(&sum0, total0);\n"
    else
      x += "    __m128 wei, inp, prod, total0, total1, total2, total3;\n"

      got = 1
      x += "    inp    = _mm_load_ps(values+#{io});\n"
      x += "    wei    = _mm_load_ps(weights+#{wo});\n"
      x += "    total0 = _mm_mul_ps(inp, wei);\n"
      len -= 4
      io += 4
      wo += 4

      while (len >= 4)
        y = 3&(io/4)
        x += "    inp   = _mm_load_ps(values+#{io});\n"
        x += "    wei   = _mm_load_ps(weights+#{wo});\n"
        
        if (0 != (got & (1<<y)))
          x += "    prod  = _mm_mul_ps(inp, wei);\n"
          x += "    total#{y} = _mm_add_ps(prod, total#{y});\n"
        else
          x += "    total#{y} = _mm_mul_ps(inp, wei);\n"
          got |= 1<<y
        end
        
        len -= 4
        io += 4
        wo += 4
      end
      
      case got
      when 3
        x += "    total0 = _mm_add_ps(total0, total1);\n"
      when 7
        x += "    total0 = _mm_add_ps(total0, total1);\n"
        x += "    total0 = _mm_add_ps(total0, total2);\n"
      when 15
        x += "    total0 = _mm_add_ps(total0, total1);\n"
        x += "    total2 = _mm_add_ps(total2, total3);\n"
        x += "    total0 = _mm_add_ps(total0, total2);\n"
      end
      
      x += "    total0 = _mm_hadd_ps(total0, total0);\n"
      x += "    total0 = _mm_hadd_ps(total0, total0);\n"
      x += "    _mm_store_ss(&sum0, total0);\n"
    end
    
    case len
    when 0
      x += "    return sum0;\n"
    when 1
      x += "    sum1 = values[#{io}] * weights[#{wo}];\n";
      x += "    return sum0 + sum1;\n"
    when 2
      x += "    sum1 = values[#{io}] * weights[#{wo}];\n";
      x += "    sum2 = values[#{io+1}] * weights[#{wo+1}];\n";
      x += "    return (sum0 + sum1) + sum2;\n"
    when 3
      x += "    sum1 = values[#{io}] * weights[#{wo}];\n";
      x += "    sum2 = values[#{io+1}] * weights[#{wo+1}];\n";
      x += "    sum3 = values[#{io+2}] * weights[#{wo+2}];\n";
      x += "    return (sum0 + sum1) + (sum2 + sum3);\n"
    end
  else
    x += "    #{$float} sum0, sum1, sum2, sum3;\n"
    got = 0
    while (len > 0)
      if ((got & (1<<(io&3))) != 0)
        x += "    sum#{io&3} += values[#{io}] * weights[#{wo}];\n";
      else
        x += "    sum#{io&3} = values[#{io}] * weights[#{wo}];\n";
        got |= 1<<(io&3)
      end
      len -= 1
      io += 1
      wo += 1
    end
    case got
    when 1
      x += "    return sum0;\n"
    when 3
      x += "    return sum0 + sum1;\n"
    when 7
      x += "    return (sum0 + sum1) + sum2;\n"
    when 15
      x += "    return (sum0 + sum1) + (sum2 + sum3);\n"
    end
  end
  
  x + "}\n\n";
end


def sum_scaled(len)
  # Emit a function that does a scaled sum
    
  io = 0
  oo = 0
  
  x = ""
  if (len > 8)
    x += "__attribute__((noinline)) "
  end
  x += "static void sum_scaled_#{len}(#{$float} *in, #{$float} *out, #{$float} scale) {\n"
    
  if $use_sse
    if $double
      if (len >= 4)
        x += "    __m128d tgt, inp, sca;\n"
        x += "    sca = _mm_set1_pd(scale);\n"
      
        while (len >= 2)
          x += "    inp = _mm_load_pd(in+#{io});\n"
          x += "    tgt = _mm_load_pd(out+#{oo});\n"
          x += "    inp = _mm_mul_pd(sca, inp);\n"
          x += "    tgt = _mm_add_pd(inp, tgt);\n"
          x += "    _mm_store_pd(out+#{oo}, tgt);\n"
        
          len -= 2
          io += 2
          oo += 2
        end
      end
    else
      if (len >= 4)
        x += "    __m128 tgt, inp, sca;\n"
        x += "    sca = _mm_set1_ps(scale);\n"
      
        while (len >= 4)
          x += "    inp = _mm_load_ps(in+#{io});\n"
          x += "    tgt = _mm_load_ps(out+#{oo});\n"
          x += "    inp = _mm_mul_ps(sca, inp);\n"
          x += "    tgt = _mm_add_ps(inp, tgt);\n"
          x += "    _mm_store_ps(out+#{oo}, tgt);\n"
        
          len -= 4
          io += 4
          oo += 4
        end
      end
    end
  end
      
  while (len > 0) 
    x += "    out[#{oo}] += scale * in[#{io}];\n"
    len -= 1
    io += 1
    oo += 1
  end
    
  x + "}\n\n"
end


def mul_sig_prime(len)
  io = 0
  oo = 0
    
  x = ""
  if (len > 8)
    x += "__attribute__((noinline)) "
  end
  x += "static void mul_sig_prime_#{len}(#{$float} *in, #{$float} *out) {\n"
  x += "    #{$float} i;\n"
    
  if $use_sse
    if $double
      if len >= 4
        x += "    __m128d tgt, inp, one;\n"
        x += "    one = _mm_set1_pd(1.0);\n"
        
        while (len >= 2)
          x += "    inp = _mm_load_pd(in+#{io});\n"
          x += "    tgt = _mm_load_pd(out+#{oo});\n"
          x += "    inp = _mm_mul_pd(inp, inp);\n"
          x += "    inp = _mm_sub_pd(one, inp);\n"
          x += "    tgt = _mm_mul_pd(inp, tgt);\n"
          x += "    _mm_store_pd(out+#{oo}, tgt);\n"

          io += 2
          oo += 2
          len -= 2
        end
      end
    else
      if len >= 4
        x += "    __m128 tgt, inp, one;\n"
        x += "    one = _mm_set1_ps(1.0f);\n"
        
        while (len >= 4)
          x += "    inp = _mm_load_ps(in+#{io});\n"
          x += "    tgt = _mm_load_ps(out+#{oo});\n"
          x += "    inp = _mm_mul_ps(inp, inp);\n"
          x += "    inp = _mm_sub_ps(one, inp);\n"
          x += "    tgt = _mm_mul_ps(inp, tgt);\n"
          x += "    _mm_store_ps(out+#{oo}, tgt);\n"

          io += 4
          oo += 4
          len -= 4
        end
      end
    end
  end
    
  while len > 0
    x += "    i = in[#{io}];\n"
    if $double
      x += "    out[#{oo}] *= 1.0 - i*i;\n"
    else
      x += "    out[#{oo}] *= 1.0f - i*i;\n"
    end
    io += 1
    oo += 1
    len -= 1
  end
    
  x + "}\n\n"
end



# NOTE:  For only four, SSE is actually slower

def sigmoid(len)
  io = 0
  x = "__attribute__((noinline)) void static sigmoid_#{len}(#{$float} *in) {\n"
  x += "    #{$float} x, x2, af, bf;\n    int i;\n"
    
  # if $use_ssex
  #   if $double
  #     if len >= 8
  #       x += "    __m128d F378, F17325, F135135, F28, F3150, F62370, Fsign, F4;\n"
  #       x += "    __m128d inp, in2, a, b, abs, sign, gt4, one, ones;\n"
  #       x += "    Fsign   = (__m128d)_mm_set1_epi64x(0x8000000000000000ULL);\n"
  #       x += "    F4      = _mm_set1_pd(4.97178);\n"
  #       x += "    F378    = _mm_set1_pd(378.0);\n"
  #       x += "    F17325  = _mm_set1_pd(17325.0);\n"
  #       x += "    F135135 = _mm_set1_pd(135135.0);\n"
  #       x += "    F28     = _mm_set1_pd(28.0);\n"
  #       x += "    F3150   = _mm_set1_pd(3150.0);\n"
  #       x += "    F62370  = _mm_set1_pd(62370.0);\n"
  #       x += "    one     = _mm_set1_pd(1.0);\n"
  #
  #       x += "    for (i=0; i<#{len / 2}; i++) {\n"
  #       x += "        inp = _mm_load_pd(in);\n"
  #       x += "        in2 = _mm_mul_pd(inp, inp);\n"
  #
  #       x += "        abs = _mm_andnot_pd(Fsign, inp);\n"
  #       x += "        gt4 = _mm_cmpgt_pd(abs, F4);\n"
  #
  #       x += "        sign = _mm_and_pd(Fsign, inp);\n"
  #       x += "        ones = _mm_or_pd(one, sign);\n"
  #
  #       x += "        a = _mm_add_pd(in2, F378);\n"
  #       x += "        a = _mm_mul_pd(a, in2);\n"
  #       x += "        a = _mm_add_pd(a, F17325);\n"
  #       x += "        a = _mm_mul_pd(a, in2);\n"
  #       x += "        a = _mm_add_pd(a, F135135);\n"
  #       x += "        a = _mm_mul_pd(a, inp);\n"
  #
  #       x += "        b = _mm_mul_pd(in2, F28);\n"
  #       x += "        b = _mm_add_pd(b, F3150);\n"
  #       x += "        b = _mm_mul_pd(b, in2);\n"
  #       x += "        b = _mm_add_pd(b, F62370);\n"
  #       x += "        b = _mm_mul_pd(b, in2);\n"
  #       x += "        b = _mm_add_pd(b, F135135);\n"
  #
  #       x += "        a = _mm_div_pd(a, b);\n"
  #
  #       x += "        a = _mm_andnot_pd(gt4, a);\n"
  #       x += "        b = _mm_and_pd(gt4, ones);\n"
  #       x += "        a = _mm_or_pd(a, b);\n"
  #       x += "        _mm_store_pd(in, a);\n"
  #
  #       x += "        in += 2;\n"
  #       x += "    }\n"
  #
  #       len &= 1
  #     end
  #   else
  #     if len >= 8
  #       x += "    __m128 F378, F17325, F135135, F28, F3150, F62370, Fsign, F4;\n"
  #       x += "    __m128 inp, in2, a, b, abs, sign, gt4, one, ones;\n"
  #       x += "    Fsign   = (__m128)_mm_set1_epi32(0x80000000);\n"
  #       x += "    F4      = _mm_set1_ps(4.97178f);\n"
  #       x += "    F378    = _mm_set1_ps(378.0f);\n"
  #       x += "    F17325  = _mm_set1_ps(17325.0f);\n"
  #       x += "    F135135 = _mm_set1_ps(135135.0f);\n"
  #       x += "    F28     = _mm_set1_ps(28.0f);\n"
  #       x += "    F3150   = _mm_set1_ps(3150.0f);\n"
  #       x += "    F62370  = _mm_set1_ps(62370.0f);\n"
  #       x += "    one     = _mm_set1_ps(1.0f);\n"
  #
  #       x += "    for (i=0; i<#{len / 4}; i++) {\n"
  #       x += "        inp = _mm_load_ps(in);\n"
  #       x += "        in2 = _mm_mul_ps(inp, inp);\n"
  #
  #       x += "        abs = _mm_andnot_ps(Fsign, inp);\n"
  #       x += "        gt4 = _mm_cmpgt_ps(abs, F4);\n"
  #
  #       x += "        sign = _mm_and_ps(Fsign, inp);\n"
  #       x += "        ones = _mm_or_ps(one, sign);\n"
  #
  #       x += "        a = _mm_add_ps(in2, F378);\n"
  #       x += "        a = _mm_mul_ps(a, in2);\n"
  #       x += "        a = _mm_add_ps(a, F17325);\n"
  #       x += "        a = _mm_mul_ps(a, in2);\n"
  #       x += "        a = _mm_add_ps(a, F135135);\n"
  #       x += "        a = _mm_mul_ps(a, inp);\n"
  #
  #       x += "        b = _mm_mul_ps(in2, F28);\n"
  #       x += "        b = _mm_add_ps(b, F3150);\n"
  #       x += "        b = _mm_mul_ps(b, in2);\n"
  #       x += "        b = _mm_add_ps(b, F62370);\n"
  #       x += "        b = _mm_mul_ps(b, in2);\n"
  #       x += "        b = _mm_add_ps(b, F135135);\n"
  #
  #       x += "        a = _mm_div_ps(a, b);\n"
  #
  #       x += "        a = _mm_andnot_ps(gt4, a);\n"
  #       x += "        b = _mm_and_ps(gt4, ones);\n"
  #       x += "        a = _mm_or_ps(a, b);\n"
  #       x += "        _mm_store_ps(in, a);\n"
  #
  #       x += "        in += 4;\n"
  #       x += "    }\n"
  #
  #       len &= 3
  #     end
  #   end
  # end
      
  if (len > 1)
    x += "    for (i=0; i<#{len}; i++) {\n"
  end
  if $double
    if (len > 0)
      x += "        x = *in;\n"
      x += "        x = tanh(x);\n"
      # x += "        if (x < -4.97178) { x = -1.0; } else if (x > 4.97178) { x = 1.0; } else {\n"
      # x += "            x2 = x * x;\n"
      # x += "            af = x * (135135.0 + x2 * (17325.0 + x2 * (378.0 + x2)));\n"
      # x += "            bf = 135135.0 + x2 * (62370.0 + x2 * (3150.0 + x2 * 28.0));\n"
      # x += "            x = af / bf;\n"
      # x += "        }\n"
      x += "        *in++ = x;\n"
    end
  else
    if (len > 0)
      x += "        x = *in;\n"
      x += "        x = tanhf(x);\n"
      # x += "        if (x < -4.97178f) { x = -1.0f; } else if (x > 4.97178f) { x = 1.0f; } else {\n"
      # x += "            x2 = x * x;\n"
      # x += "            af = x * (135135.0f + x2 * (17325.0f + x2 * (378.0f + x2)));\n"
      # x += "            bf = 135135.0f + x2 * (62370.0f + x2 * (3150.0f + x2 * 28.0f));\n"
      # x += "            x = af / bf;\n"
      # x += "        }\n"
      x += "        *in++ = x;\n"
    end
  end
  if (len > 1)
    x += "    }\n"
  end
    
  x + "}\n\n"
end


def allocate_func_h(size, name)
  x  = "#{$float} *allocate_#{name}();\n";
  x += "void free_#{name}(#{$float} *mem);\n"
  x += "#define MEM_SIZE_#{name} ( #{size} * sizeof(#{$float}) )\n"
  x
end

def allocate_func(size, name)
  x = "#{$float} *allocate_#{name}() {\n";
  if $use_sse
    x += "    return (#{$float} *)_mm_malloc(#{size} * sizeof(#{$float}), 16);\n"
  else
    x += "    return (#{$float} *)malloc(#{size} * sizeof(#{$float}));\n"
  end
  x += "}\n\n"
  x += "void free_#{name}(#{$float} *mem) {\n";
  if $use_sse
    x += "    _mm_free(mem);\n"
  else
    x += "    free(mem);\n"
  end
  x += "}\n\n"
  x
end

def randomize_h(size, name)
  "void randomize_#{name}(#{$float} *mem);\n"
end

# def randomize(size, name)
#   x  = "void randomize_#{name}(#{$float} *mem) {\n"
#   x += "    const double RMI = 1.0 / RAND_MAX;\n"
#   x += "    double b2 = pow(#{size}, -0.5L) * sqrt(12.0L);\n"
#   x += "    double b = b2*0.5;\n"
#   x += "    int i;\n"
#   x += "    for (i=0; i<#{size}; i++) {\n"
#   x += "        do {\n"
#   //    x += "            mem[i] = (double)random() / ((double)RAND_MAX);\n"
#   x += "            mem[i] = ((random() * RMI) * b2 - b);\n"
#   x += "        } while (mem[i] == 0);\n"
#   x += "    }\n"
#   x += "}\n\n"
#   x
# end


class Layer
  # Inputs
  attr_accessor :n_in, :in_val, :in_del
  # Outputs
  attr_accessor :n_out, :out_val, :out_del, :sig
  # Weights
  attr_accessor :weights
  attr_accessor :mynum
  # Other
  attr_accessor :quantize, :quanti, :quantf
    
  def initialize
    @weights = []
  end
end

class LayerSpec
  attr_accessor :size, :quantize, :quanti, :quantf, :sigmoid

  def initialize(word)
    @quantize = false
    @sigmoid = true
    @quanti = 0
    @quantf = 0

    word = word.downcase.scan(/./)

    size_s = ""
    while word.size > 0 && word[0] =~ /[[:digit:]]/
      size_s << word[0]
      word.shift
    end
    @size = size_s.to_i

    if word.size > 0 && word[0] =~ /[ls]/
      @sigmoid = false if word[0] == 'l'
      word.shift
    end

    if word.size > 0 && word[0] == 'q'
      @quantize = true
      i_s = ""
      f_s = ""
      while word.size > 0 && word[0] != '.'
        i_s << word[0]
        word.shift
      end
      @quanti = i_s.to_i
      word.shift if word.size > 0
      while word.size > 0
        f_s << word[0]
        word.shift
      end
      @quantf = f_s.to_i
    end
  end

  def comment
    x = "#{@size} nodes"
    if @sigmoid
      x += ", tanh activation"
    else
      x += ", linear activation"
    end
    if @quantize
      x += ", quantized to #{@quanti}.#{@quantf}"
    end
    x
  end

  def to_s
    "#{@size}#{@sigmoid ? 's' : 'l'}#{@quantize ? "q" : ""}"
  end
end


class Network
  # Data
  attr_accessor :layers, :name, :outsig, :in_tmp, :mem_size, :out_tmp

  # Pending needs
  attr_accessor :need_dotprod, :need_sum_scaled, :need_mul_sig_prime
  attr_accessor :need_subtract, :need_subtract_sig, :need_sigmoid
  attr_accessor :need_copy, :need_clear

  # Functions
  attr_accessor :allocator, :funcs, :fwd, :defines, :bkw, :code
    
  def randomize_n(size)
    # Actually randomizes size+1 values, to include the bias
    x = ""
    if (size > 8)
        x += "__attribute__((noinline)) "
    end
    x += "static void randomize_#{size}(#{$float} *mem) {\n"
    x += "    const double RMI = 1.0 / RAND_MAX;\n"
    x += "    double b2 = pow((double)#{size}, -0.5) * sqrt(12.0);\n"
    x += "    double b = b2*0.5;\n"
    x += "    b2 *= RMI;\n"
    x += "    int i;\n"
    x += "    for (i=0; i<=#{size}; i++) {\n"
    x += "        do {\n"
    x += "            mem[i] = random() * b2 - b;\n"
    x += "        } while (mem[i] == 0);\n"
    x += "    }\n"
    x += "}\n\n"
    x
  end
    
  def randomize
    needrandom = []
    @layers.each_index do |ln|
      layer = @layers[ln]
      needrandom << layer.n_in
    end
    needrandom.uniq!

    x = ""
    needrandom.each do |n|
      x += randomize_n(n)
    end
      
    x += "__attribute__((noinline)) "
    x += "void randomize_#{@name}(#{$float} *mem) {\n"
    @layers.each_index do |ln|
      layer = @layers[ln];
      layer.weights.each do |w|
        x += "    randomize_#{layer.n_in}(#{w});\n"
      end
    end
    x += "}\n\n"
    x
  end
  
  def initialize(layer_list)
    @mem_size = 0
    @need_sigmoid = []
    @need_dotprod = []
    @need_sum_scaled = []
    @need_mul_sig_prime = []
    @need_subtract = []
    @need_subtract_sig = []
    @need_copy = []
    @need_clear = []
    @need_quantize = []
        
    @defines = allocate(layer_list)
    @out_tmp = "(mem+#{allocate_block(layer_list[-1].size)})"
    @defines += "#define OUT_TMP #{@out_tmp}\n\n"
    @fwd = forward
    @bkw = backward
        
    @need_sigmoid.uniq!
    @need_dotprod.uniq!
    @need_sum_scaled.uniq!
    @need_mul_sig_prime.uniq!
    @need_subtract.uniq!
    @need_subtract_sig.uniq!
    @need_copy.uniq!
    @need_clear.uniq!
    @need_quantize.uniq!
        
    @allocator = allocate_func(@mem_size, @name)
    @funcs = @allocator
    @funcs += randomize #(@mem_size, @name)
    @need_quantize.each { |i| @funcs += quantize(i[0], i[1], i[2]); }
    @need_sigmoid.each { |i| @funcs += sigmoid(i); }
    @need_dotprod.each { |i| @funcs += dotprod(i); }
    @need_sum_scaled.each { |i| @funcs += sum_scaled(i); }
    @need_mul_sig_prime.each { |i| @funcs += mul_sig_prime(i); }
    @need_subtract.each { |i| @funcs += subtract(i); }
    @need_subtract_sig.each { |i| @funcs += subtract_sig(i); }
    @need_copy.each { |i| @funcs += memcpy(i); }
    @need_clear.each { |i| @funcs += memclr(i); }
        
    @code = "#ifndef ANN_HEADER\n\n"
    if ($use_sse)
      @code += "#include <pmmintrin.h>\n"
    end
    @code += "#include <math.h>\n#include <stdlib.h>\n#include <stdio.h>\n#include <string.h>\n\n"
    @code += @defines + @funcs + @fwd + @bkw
    @code += "\n#else /* HEADER FOLLOWS */\n\n"
    @code += allocate_func_h(@mem_size, @name)
    @code += forward_h
    @code += backward_h
    @code += randomize_h(@mem_size, @name)
    @code += "\n#endif\n"
  end

  def allocate_block(n)
    start = @mem_size
    @mem_size += n
    x = @mem_size & 3
    if (x != 0)
      @mem_size += 4-x
    end
    start
  end
    
    
  def allocate(layer_list)
    @name = layer_list.map{|l| l.to_s}.join("_")
    #@name = layer_list.join("_") + (outsig ? "s" : "l")
        
    # Find homes for all values, weights, and deltas
    @needs_dotprod = []
    @layers = []
    
    # Previous layer
    l = layer_list.clone
    prev_nnodes = l.shift.size
    @in_tmp = "(mem+#{allocate_block(prev_nnodes)})"
    x = "#define IN_TMP #{@in_tmp}\n"
    @in_tmp = "IN_TMP"
    prev_val = "IN_TMP"
    prev_del = nil
        
    ln = 1
            
    while (l.size > 0)
      layerspec = l.shift
      nnodes = layerspec.size
      values = allocate_block(nnodes)
      val_ptr = "(mem+#{values})"
      x += "#define L#{ln}_VAL #{val_ptr}\n"
      val_ptr = "L#{ln}_VAL"
            
      deltas = allocate_block(nnodes)
      del_ptr = "(mem+#{deltas})"
      x += "#define L#{ln}_DEL #{del_ptr}\n"
      del_ptr = "L#{ln}_DEL"
            
      layer = Layer.new
      layer.n_in = prev_nnodes
      layer.n_out = nnodes
      layer.in_val = prev_val
      layer.out_val = val_ptr
      layer.in_del = prev_del
      layer.out_del = del_ptr
      layer.quantize = layerspec.quantize
      layer.quanti = layerspec.quanti
      layer.quantf = layerspec.quantf
      layer.sig = layerspec.sigmoid
      layer.mynum = @layers.size
            
      for i in 0...nnodes do
        weights = allocate_block(prev_nnodes + 1)
        n = "(mem+#{weights})"
        x += "#define L#{ln}_N#{i}_WEIGHTS #{n}\n"
        layer.weights << "L#{ln}_N#{i}_WEIGHTS"
      end
            
      @layers << layer
            
      prev_nnodes = nnodes
      prev_val = val_ptr
      prev_del = del_ptr
            
      ln += 1
    end
        
    x
  end

  def forward_h
    x = ""
    layers.each do |layer|
      x += "#{$float} *forward_L#{layer.mynum}_#{@name}(#{$float} *mem);\n"
    end
    x + "#{$float} *forward_#{@name}(#{$float} *in, #{$float} *mem);\n"
  end
    
  def forward
    @need_copy << layers.first.n_in
    x = ""

    layers.each do |layer|
      x += "__attribute__((noinline)) "
      x += "#{$float} *forward_L#{layer.mynum}_#{@name}(#{$float} *mem) {\n"

      nnodes = layer.n_out
      prev_nnodes = layer.n_in
      ptr = layer.out_val
            
      @need_dotprod << prev_nnodes
            
      for i in 0...nnodes do
        weights = layer.weights[i]
        x += "    *(#{ptr}+#{i}) = "
        x += "dotprod_#{prev_nnodes}(#{weights}, #{layer.in_val}) "
        x += "+ *(#{weights}+#{layer.n_in});\n";
      end
            
      if (layer.sig)
        @need_sigmoid << nnodes
        x += "    sigmoid_#{nnodes}(#{ptr});\n"
      end

      if (layer.quantize)
        @need_quantize << [nnodes, layer.quanti, layer.quantf]
        x += "    quantize_#{nnodes}_#{layer.quanti}_#{layer.quantf}(#{ptr});\n"
      end

      x += "    return #{layer.out_val};\n"
      
      x += "}\n\n"
    end
        
    x += "__attribute__((noinline)) "
    x += "#{$float} *forward_#{@name}(#{$float} *in, #{$float} *mem) {\n"
    x += "    memory_copy_#{layers.first.n_in}(#{@in_tmp}, in);\n"
    #x += "    memcpy(#{@in_tmp}, in, sizeof(float) * #{layers.first.n_in});\n"

    layers.each_index do |i|
      layer = layers[i]
      ret = (i == layers.size-1) ? "return " : "";
      x += "    #{ret}forward_L#{layer.mynum}_#{@name}(mem);\n"
    end
    #x += "    return #{layers.last.out_val};\n"

    x += "}\n\n"
    
    x
  end

  def backward_h
    "void backward_#{@name}(#{$float} *desired_in, #{$float} *mem, #{$float} lr);\n"
  end
    
  def backward
    x = "__attribute__((noinline)) "
    x += "void backward_#{@name}(#{$float} *desired, #{$float} *mem, #{$float} lr) {\n"
    x += "    #{$float} odel;\n"
    @need_copy << layers.last.n_out
    x += "    memory_copy_#{layers.last.n_out}(OUT_TMP, desired);\n\n"
        
    # Compute output deltas from output values and desired
    out_del = layers.last.out_del
    out_val = layers.last.out_val
    n_out = layers.last.n_out
    x += "    /* Compute output deltas */\n"
    if (layers.last.sig)
      @need_subtract_sig << n_out
      x += "    subtract_sig_#{n_out}(OUT_TMP, #{out_val}, #{out_del});\n"
    else
      @need_subtract << n_out
      x += "    subtract_#{n_out}(OUT_TMP, #{out_val}, #{out_del});\n"
    end
        
    # Loop backward over layers, computing deltas
    ls = layers.clone
    ls.shift
    while (ls.size > 0)
      x += "\n    /* Layer deltas */\n"
      l = ls.pop
      @need_sum_scaled << l.n_in
      @need_clear << l.n_in
      #x += "    memset(#{l.in_del}, 0, sizeof(float) * #{l.n_in});\n"
      x += "    memory_clear_#{l.n_in}(#{l.in_del});\n"
      for i in 0...l.n_out
        x += "    sum_scaled_#{l.n_in}(#{l.weights[i]}, #{l.in_del}, "
        x += "*(#{l.out_del}+#{i}));\n"
      end
      @need_mul_sig_prime << l.n_in
      x += "    mul_sig_prime_#{l.n_in}(#{l.in_val}, #{l.in_del});\n"
    end
        
    # Loop over layers, adjusting weights
    ls = layers.clone
    inputs = @in_tmp
    ls.each do |l|
      x += "\n    /* Adjust weights */\n"
      @need_sum_scaled << l.n_in
      for i in 0...l.n_out
        x += "    odel = *(#{l.out_del}+#{i}) * lr;"
        #x += "if (odel > 1) printf(\"odel #{i} L#{l.mynum} = %f\\n\", odel);";
        # if (i == 1 && l.mynum == 0)
        #   x += "printf(\"%f\\n\", odel);\n"
        # end
        x += "    sum_scaled_#{l.n_in}(#{inputs}, "
        x += "#{l.weights[i]}, odel);"
        x += "    *(#{l.weights[i]}+#{l.n_in}) += odel;\n"
      end
      inputs = l.out_val
    end
        
    x + "}\n\n"
  end
end

layers = []

ARGV.each do |arg|
  layers << LayerSpec.new(arg)
end

layers.each_index do |i|
  puts "// Layer #{i}: #{layers[i].comment}"
end
puts

net = Network.new(layers)
print net.code

=begin
layers = ARGV.clone

do_quantize = []
if (layers.last.downcase[0] == 'q')
  q = layers.last.scan(/./)
  q.shift
  q.each_index do |i|
    do_quantize[i] = q[i] == '1'
  end
  layers.pop
end

sigout = false
if (layers.last.downcase == "s")
  sigout = true
  layers.pop
end

layers2 = layers.map {|x| x.to_i}
net = Network.new(layers2, sigout, do_quantize)
print net.code
=end

# Load configuration
# Allocate block for values
# Allocate block for weights
# Allocate block for deltas
# Determine all dotprod functions that will be needed
# Determine all sum_scaled functions needed
