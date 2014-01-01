# Bidiagonal matrices
type Bidiagonal{T} <: AbstractMatrix{T}
    dv::AbstractVector{T} # diagonal
    ev::AbstractVector{T} # sub/super diagonal
    isupper::Bool # is upper bidiagonal (true) or lower (false)
    function Bidiagonal{T}(dv::AbstractVector{T}, ev::AbstractVector{T}, isupper::Bool)
        length(ev)==length(dv)-1 ? new(dv, ev, isupper) : throw(DimensionMismatch(""))
    end
end

Bidiagonal{T}(dv::AbstractVector{T}, ev::AbstractVector{T}, isupper::Bool)=Bidiagonal{T}(copy(dv), copy(ev), isupper)
Bidiagonal{T}(dv::AbstractVector{T}, ev::AbstractVector{T}) = error("Did you want an upper or lower Bidiagonal? Try again with an additional true (upper) or false (lower) argument.")

#Convert from BLAS uplo flag to boolean internal
function Bidiagonal(dv::AbstractVector, ev::AbstractVector, uplo::BlasChar)
    if uplo=='U'
        return Bidiagonal(copy(dv), copy(ev), true)
    elseif uplo=='L'
        return Bidiagonal(copy(dv), copy(ev), false)
    else
        error("Bidiagonal can only be upper 'U' or lower 'L' but you said '$uplo''")
    end
end

    T = promote(Td,Te)
function Bidiagonal{Td,Te}(dv::AbstractVector{Td}, ev::AbstractVector{Te}, isupper::Bool)
    Bidiagonal(convert(Vector{T}, dv), convert(Vector{T}, ev), isupper)
end

Bidiagonal(A::AbstractMatrix, isupper::Bool)=Bidiagonal(diag(A), diag(A, isupper?1:-1), isupper)

#Converting from Bidiagonal to dense Matrix
full{T}(M::Bidiagonal{T}) = convert(Matrix{T}, M)
convert{T}(::Type{Matrix{T}}, A::Bidiagonal{T})=diagm(A.dv) + diagm(A.ev, A.isupper?1:-1)
promote_rule{T,S}(::Type{Matrix{T}}, ::Type{Bidiagonal{S}})=Matrix{promote_type(T,S)}

#Converting from Bidiagonal to Tridiagonal
Tridiagonal{T}(M::Bidiagonal{T}) = convert(Tridiagonal{T}, M)
function convert{T}(::Type{Tridiagonal{T}}, A::Bidiagonal{T})
    z = zeros(T, size(A)[1]-1)
    A.isupper ? Tridiagonal(A.ev, A.dv, z) : Tridiagonal(z, A.dv, A.ev)
end
promote_rule{T,S}(::Type{Tridiagonal{T}}, ::Type{Bidiagonal{S}})=Tridiagonal{promote_type(T,S)}

#################
# BLAS routines #
#################

#Singular values
svdvals{T<:Real}(M::Bidiagonal{T})=LAPACK.bdsdc!(M.isupper?'U':'L', 'N', copy(M.dv), copy(M.ev))
svd    {T<:Real}(M::Bidiagonal{T})=LAPACK.bdsdc!(M.isupper?'U':'L', 'I', copy(M.dv), copy(M.ev))

####################
# Generic routines #
####################

function show(io::IO, M::Bidiagonal)
    println(io, summary(M), ":")
    print(io, " diag:")
    print_matrix(io, (M.dv)')
    print(io, M.isupper?"\nsuper:":"\n  sub:")
    print_matrix(io, (M.ev)')
end

size(M::Bidiagonal) = (length(M.dv), length(M.dv))
size(M::Bidiagonal, d::Integer) = d<1 ? error("dimension out of range") : (d<=2 ? length(M.dv) : 1)

#Elementary operations
for func in (conj, copy, round, iround)
    func(M::Bidiagonal) = Bidiagonal(func(M.dv), func(M.ev), M.isupper)
end

transpose(M::Bidiagonal) = Bidiagonal(M.dv, M.ev, !M.isupper)
ctranspose(M::Bidiagonal) = Bidiagonal(conj(M.dv), conj(M.ev), !M.isupper)

function +(A::Bidiagonal, B::Bidiagonal)
    if A.isupper==B.isupper
        Bidiagonal(A.dv+B.dv, A.ev+B.ev, A.isupper)
    else
        apply(Tridiagonal, A.isupper ? (B.ev,A.dv+B.dv,A.ev) : (A.ev,A.dv+B.dv,B.ev))
    end
end

function -(A::Bidiagonal, B::Bidiagonal)
    if A.isupper==B.isupper
        Bidiagonal(A.dv-B.dv, A.ev-B.ev, A.isupper)
    else
        apply(Tridiagonal, A.isupper ? (-B.ev,A.dv-B.dv,A.ev) : (A.ev,A.dv-B.dv,-B.ev))
    end
end

-(A::Bidiagonal)=Bidiagonal(-A.dv,-A.ev)
*(A::Bidiagonal, B::Number) = Bidiagonal(A.dv*B, A.ev*B, A.isupper)
*(B::Number, A::Bidiagonal) = A*B
/(A::Bidiagonal, B::Number) = Bidiagonal(A.dv/B, A.ev/B, A.isupper)
==(A::Bidiagonal, B::Bidiagonal) = (A.dv==B.dv) && (A.ev==B.ev) && (A.isupper==B.isupper)

SpecialMatrix = Union(Diagonal, Bidiagonal, SymTridiagonal, Tridiagonal, Triangular)
*(A::SpecialMatrix, B::SpecialMatrix)=full(A)*full(B)

\(M::Bidiagonal, rhs::StridedVecOrMat)=Tridiagonal(M)\rhs

# Eigensystems
eigvals{T<:Number}(M::Bidiagonal{T}) = M.isupper ? M.dv : reverse(M.dv)
function eigvecs{T<:Number}(M::Bidiagonal{T})
    n = length(M.dv)
    Q=zeros(T, n, n)
    v=zeros(T, n)
    if M.isupper
        for i=1:n #index of eigenvector
            v[1] = convert(T, 1.0)
            for j=1:i-1 #Starting from j=i, eigenvector elements will be 0
                v[j+1] = (M.dv[i]-M.dv[j])/M.ev[j] * v[j]
            end
            v /= norm(v)
            Q[:,i] = v
        end
    else
        for i=n:-1:1 #index of eigenvector
            v[n] = convert(T, 1.0)
            for j=(n-1):-1:max(1,(i-1)) #Starting from j=i-1, eigenvector elements will be 0
                v[j] = (M.dv[i]-M.dv[j+1])/M.ev[j] * v[j+1]
            end
            v /= norm(v)
            Q[:,n+1-i] = v
        end
    end
    Q
end
eigfact(M::Bidiagonal) = Eigen(eigvals(M), eigvecs(M))

#Singular values
function svdfact(M::Bidiagonal, thin::Bool=true)
    U, S, V = svd(M)
    SVD(U, S, V')
end
