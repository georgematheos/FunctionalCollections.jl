# `shiftby` is equal to the number of bits required to represent index information
# for one level of the BitmappedTrie.
#
# Here, `shiftby` is 5, which means that the BitmappedTrie Arrays will be length 32.
const shiftby = 5
const trielen = 2^shiftby

abstract BitmappedTrie{T}
abstract DenseBitmappedTrie{T} <: BitmappedTrie{T}
abstract SparseBitmappedTrie{T} <: BitmappedTrie{T}

# Bitmapped Tries
#
immutable DenseNode{T} <: DenseBitmappedTrie{T}
    self::Array{DenseBitmappedTrie{T}, 1}
    shift::Int
    length::Int
    maxlength::Int
end
DenseNode{T}() = DenseNode{T}(DenseBitmappedTrie{T}[], shiftby*2, 0, trielen)

immutable DenseLeaf{T} <: DenseBitmappedTrie{T}
    self::Array{T, 1}

    DenseLeaf(self::Array) = new(self)
    DenseLeaf() = new(T[])
end

immutable SparseNode{T} <: SparseBitmappedTrie{T}
    self::Array{SparseBitmappedTrie{T}, 1}
    shift::Int
    length::Int
    maxlength::Int
    bitmap::Int
end
SparseNode{T}() = SparseNode{T}(SparseBitmappedTrie{T}[], shiftby*2, 0, trielen, 0)

immutable SparseLeaf{T} <: SparseBitmappedTrie{T}
    self::Array{T, 1}
    bitmap::Int

    SparseLeaf(self::Array, bitmap::Int) = new(self, bitmap)
    SparseLeaf() = new(T[], 0)
end

shift(n::Union(DenseNode, SparseNode)) = n.shift
maxlength(n::Union(DenseNode, SparseNode)) = n.maxlength
Base.length(n::Union(DenseNode, SparseNode)) = n.length

shift(::Union(DenseLeaf, SparseLeaf)) = 5
maxlength(l::Union(DenseLeaf, SparseLeaf)) = trielen
Base.length(l::Union(DenseLeaf, SparseLeaf)) = length(l.self)

mask(t::BitmappedTrie, i::Int) = (((i - 1) >>> shift(t)) & (trielen - 1)) + 1

Base.endof(t::BitmappedTrie) = length(t)

function Base.isequal(t1::BitmappedTrie, t2::BitmappedTrie)
    length(t1)    == length(t2)    &&
    shift(t1)     == shift(t2)     &&
    maxlength(t1) == maxlength(t2) &&
    t1.self       == t2.self
end

# Dense Bitmapped Tries
# =====================

promoted{T}(n::DenseBitmappedTrie{T}) =
    DenseNode{T}(DenseBitmappedTrie{T}[n], shift(n) + shiftby, length(n), maxlength(n) * trielen)

demoted{T}(n::DenseNode{T}) =
    if shift(n) == shiftby * 2
        DenseLeaf{T}(T[])
    else
        DenseNode{T}(DenseBitmappedTrie{T}[], shift(n) - shiftby, 0, int(maxlength(n) / trielen))
    end

withself{T}(n::DenseNode{T}, self::Array) = withself(n, self, 0)
withself{T}(n::DenseNode{T}, self::Array, lenshift::Int) =
    DenseNode{T}(self, shift(n), length(n) + lenshift, maxlength(n))

withself{T}(l::DenseLeaf{T}, self::Array) = DenseLeaf{T}(self)

# Copy elements from one Array to another, up to `n` elements.
#
function copy_to{T}(from::Array{T}, to::Array{T}, n::Int)
    for i=1:n
        to[i] = from[i]
    end
    to
end

# Copies elements from one Array to another of size `len`.
#
copy_to_len{T}(from::Array{T}, len::Int) =
    copy_to(from, Array(T, len), min(len, length(from)))

function append{T}(l::DenseLeaf{T}, el::T)
    if length(l) < maxlength(l)
        newself = copy_to_len(l.self, 1 + length(l))
        newself[end] = el
        withself(l, newself)
    else
        append(promoted(l), el)
    end
end
function append{T}(n::DenseNode{T}, el::T)
    if length(n) == 0
        child = append(demoted(n), el)
        withself(n, DenseBitmappedTrie{T}[child], 1)
    elseif length(n) < maxlength(n)
        if length(n.self[end]) == maxlength(n.self[end])
            newself = copy_to_len(n.self, 1 + length(n.self))
            newself[end] = append(demoted(n), el)
            withself(n, newself, 1)
        else
            newself = n.self[:]
            newself[end] = append(newself[end], el)
            withself(n, newself, 1)
        end
    else
        append(promoted(n), el)
    end
end
push = append

Base.getindex(l::DenseLeaf, i::Int) = l.self[mask(l, i)]
Base.getindex(n::DenseNode, i::Int) = n.self[mask(n, i)][i]

function update{T}(l::DenseLeaf{T}, i::Int, el::T)
    newself = l.self[:]
    newself[mask(l, i)] = el
    DenseLeaf{T}(newself)
end
function update{T}(n::DenseNode{T}, i::Int, el::T)
    newself = n.self[:]
    idx = mask(n, i)
    newself[idx] = update(newself[idx], i, el)
    withself(n, newself)
end

peek(bt::DenseBitmappedTrie) = bt[end]

# Pop is usually destructive, but that doesn't make sense for an immutable
# structure, so `pop` is defined to return a Trie without its last
# element. Use `peek` to access the last element.
#
pop(l::DenseLeaf) = withself(l, l.self[1:end-1])
function pop(n::DenseNode)
    newself = n.self[:]
    newself[end] = pop(newself[end])
    withself(n, newself, -1)
end

# Sparse Bitmapped Tries
# ======================

bitpos(t::SparseBitmappedTrie, i::Int) = 1 << (mask(t, i) - 1)
index(t::SparseBitmappedTrie, i::Int) =
    1 + count_ones(t.bitmap & (bitpos(t, i) - 1))
