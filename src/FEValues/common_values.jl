# Common methods for all `AbstractValues` objects

using Base: @propagate_inbounds

@noinline throw_detJ_not_pos(detJ) = throw(ArgumentError("det(J) is not positive: det(J) = $(detJ)"))

function checkquadpoint(fe_v::AbstractValues, qp::Int)
    0 < qp <= getnquadpoints(fe_v) || error("quadrature point out of range")
    return nothing
end

@inline function reinit_needs_cell(fe_values::AbstractValues)
    # TODO: Might need better logic for this, but for current implementations this
    # is ok. If someone implements a non-identity mapping that doesn't require the cell
    # as input, this is only a slight performance issue in some cases.
    return !isa(mapping_type(get_fun_values(fe_values)), IdentityMapping)
end

@noinline function throw_incompatible_dof_length(length_ue, n_base_funcs)
    msg = "the number of base functions ($(n_base_funcs)) does not match the length " *
        "of the vector ($(length_ue)). Perhaps you passed the global vector, " *
        "or forgot to pass a dof_range?"
    throw(ArgumentError(msg))
end
@noinline function throw_incompatible_coord_length(length_x, n_base_funcs)
    msg = "the number of (geometric) base functions ($(n_base_funcs)) does not match " *
        "the number of coordinates in the vector ($(length_x)). Perhaps you forgot to " *
        "use an appropriate geometric interpolation when creating FE values? See " *
        "https://github.com/Ferrite-FEM/Ferrite.jl/issues/265 for more details."
    throw(ArgumentError(msg))
end

"""
    ValuesUpdateFlags(ip_fun::Interpolation; update_gradients = Val(true), update_hessians = Val(false), update_detJdV = Val(true))

Creates a singleton type for specifying what parts of the AbstractValues should be updated. Note that this is internal
API used to get type-stable construction. Keyword arguments in `AbstractValues` constructors are forwarded, and the public API
is passing these as `Bool`, while the `ValuesUpdateFlags` method supports both boolean and `Val(::Bool)` keyword args.
"""
function ValuesUpdateFlags(ip_fun::Interpolation; update_gradients = Val(true), update_hessians = Val(false), update_detJdV = Val(true))
    toval(v::Bool) = Val(v)
    toval(V::Val) = V
    return ValuesUpdateFlags(ip_fun, toval(update_gradients), toval(update_hessians), toval(update_detJdV))
end
function ValuesUpdateFlags(
        ip_fun::Interpolation, ::Val{update_gradients}, ::Val{update_hessians}, ::Val{update_detJdV}
    ) where {update_gradients, update_hessians, update_detJdV}
    FunDiffOrder = update_hessians ? 2 : (update_gradients ? 1 : 0)
    GeoDiffOrder = max(required_geo_diff_order(mapping_type(ip_fun), FunDiffOrder), update_detJdV)
    return ValuesUpdateFlags{FunDiffOrder, GeoDiffOrder, update_detJdV}()
end

"""
    reinit!(cv::CellValues, cell::AbstractCell, x::AbstractVector)
    reinit!(cv::CellValues, x::AbstractVector)
    reinit!(fv::FacetValues, cell::AbstractCell, x::AbstractVector, facet::Int)
    reinit!(fv::FacetValues, x::AbstractVector, function_gradient::Int)

Update the `CellValues`/`FacetValues` object for a cell or facet with cell coordinates `x`.
The derivatives of the shape functions, and the new integration weights are computed.
For interpolations with non-identity mappings, the current `cell` is also required.
"""
reinit!

"""
    getnquadpoints(fe_v::AbstractValues)

Return the number of quadrature points. For `FacetValues`,
this is the number for the current facet.
"""
function getnquadpoints end

"""
    getdetJdV(fe_v::AbstractValues, q_point::Int)

Return the product between the determinant of the Jacobian and the quadrature
point weight for the given quadrature point: ``\\det(J(\\mathbf{x})) w_q``.

This value is typically used when one integrates a function on a
finite element cell or facet as

``\\int\\limits_\\Omega f(\\mathbf{x}) d \\Omega \\approx \\sum\\limits_{q = 1}^{n_q} f(\\mathbf{x}_q) \\det(J(\\mathbf{x})) w_q``
``\\int\\limits_\\Gamma f(\\mathbf{x}) d \\Gamma \\approx \\sum\\limits_{q = 1}^{n_q} f(\\mathbf{x}_q) \\det(J(\\mathbf{x})) w_q``

"""
function getdetJdV end

"""
    shape_value(fe_v::AbstractValues, q_point::Int, base_function::Int)

Return the value of shape function `base_function` evaluated in
quadrature point `q_point`.
"""
shape_value(fe_v::AbstractValues, q_point::Int, base_function::Int)

"""
    geometric_value(fe_v::AbstractValues, q_point, base_function::Int)

Return the value of the geometric shape function `base_function` evaluated in
quadrature point `q_point`.
"""
geometric_value(fe_v::AbstractValues, q_point::Int, base_function::Int)


"""
    shape_gradient(fe_v::AbstractValues, q_point::Int, base_function::Int)

Return the gradient of shape function `base_function` evaluated in
quadrature point `q_point`.
"""
shape_gradient(fe_v::AbstractValues, q_point::Int, base_function::Int)

"""
    shape_symmetric_gradient(fe_v::AbstractValues, q_point::Int, base_function::Int)

Return the symmetric gradient of shape function `base_function` evaluated in
quadrature point `q_point`.
"""
function shape_symmetric_gradient end

"""
    shape_divergence(fe_v::AbstractValues, q_point::Int, base_function::Int)

Return the divergence of shape function `base_function` evaluated in
quadrature point `q_point`.
"""
@propagate_inbounds function shape_divergence(cv::AbstractValues, q_point::Int, base_func::Int)
    return divergence_from_gradient(shape_gradient(cv, q_point, base_func))
end
divergence_from_gradient(grad::Vec) = sum(grad)
divergence_from_gradient(grad::Tensor{2}) = tr(grad)

"""
    shape_curl(fe_v::AbstractValues, q_point::Int, base_function::Int)

Return the curl of shape function `base_function` evaluated in
quadrature point `q_point`.
"""
function shape_curl(cv::AbstractValues, q_point::Int, base_func::Int)
    return curl_from_gradient(shape_gradient(cv, q_point, base_func))
end
curl_from_gradient(∇v::SecondOrderTensor{3}) = Vec{3}((∇v[3, 2] - ∇v[2, 3], ∇v[1, 3] - ∇v[3, 1], ∇v[2, 1] - ∇v[1, 2]))
curl_from_gradient(∇v::SecondOrderTensor{2}) = Vec{1}((∇v[2, 1] - ∇v[1, 2],)) # Alternatively define as Vec{3}((0, 0, v))

"""
    function_value(fe_v::AbstractValues, q_point::Int, u::AbstractVector, [dof_range])

Compute the value of the function in a quadrature point. `u` is a vector with values
for the degrees of freedom. For a scalar valued function, `u` contains scalars.
For a vector valued function, `u` can be a vector of scalars (for use of `VectorValues`)
or `u` can be a vector of `Vec`s (for use with ScalarValues).

The value of a scalar valued function is computed as ``u(\\mathbf{x}) = \\sum\\limits_{i = 1}^n N_i (\\mathbf{x}) u_i``
where ``u_i`` are the value of ``u`` in the nodes. For a vector valued function the value is calculated as
``\\mathbf{u}(\\mathbf{x}) = \\sum\\limits_{i = 1}^n N_i (\\mathbf{x}) \\mathbf{u}_i`` where ``\\mathbf{u}_i`` are the
nodal values of ``\\mathbf{u}``.
"""
function function_value(fe_v::AbstractValues, q_point::Int, u::AbstractVector, dof_range = eachindex(u))
    n_base_funcs = getnbasefunctions(fe_v)
    length(dof_range) == n_base_funcs || throw_incompatible_dof_length(length(dof_range), n_base_funcs)
    @boundscheck checkbounds(u, dof_range)
    @boundscheck checkquadpoint(fe_v, q_point)
    val = function_value_init(fe_v, u)
    @inbounds for (i, j) in pairs(dof_range)
        val += shape_value(fe_v, q_point, i) * u[j]
    end
    return val
end

"""
    shape_value_type(fe_v::AbstractValues)

Return the type of `shape_value(fe_v, q_point, base_function)`
"""
function shape_value_type(fe_v::AbstractValues)
    # Default fallback
    return typeof(shape_value(fe_v, 1, 1))
end

function_value_init(cv::AbstractValues, ::AbstractVector{T}) where {T} = zero(shape_value_type(cv)) * zero(T)

"""
    function_gradient(fe_v::AbstractValues{dim}, q_point::Int, u::AbstractVector, [dof_range])

Compute the gradient of the function in a quadrature point. `u` is a vector with values
for the degrees of freedom. For a scalar valued function, `u` contains scalars.
For a vector valued function, `u` can be a vector of scalars (for use of `VectorValues`)
or `u` can be a vector of `Vec`s (for use with ScalarValues).

The gradient of a scalar function or a vector valued function with use of `VectorValues` is computed as
``\\mathbf{\\nabla} u(\\mathbf{x}) = \\sum\\limits_{i = 1}^n \\mathbf{\\nabla} N_i (\\mathbf{x}) u_i`` or
``\\mathbf{\\nabla} u(\\mathbf{x}) = \\sum\\limits_{i = 1}^n \\mathbf{\\nabla} \\mathbf{N}_i (\\mathbf{x}) u_i`` respectively,
where ``u_i`` are the nodal values of the function.
For a vector valued function with use of `ScalarValues` the gradient is computed as
``\\mathbf{\\nabla} \\mathbf{u}(\\mathbf{x}) = \\sum\\limits_{i = 1}^n \\mathbf{u}_i \\otimes \\mathbf{\\nabla} N_i (\\mathbf{x})``
where ``\\mathbf{u}_i`` are the nodal values of ``\\mathbf{u}``.
"""
function function_gradient(fe_v::AbstractValues, q_point::Int, u::AbstractVector, dof_range = eachindex(u))
    n_base_funcs = getnbasefunctions(fe_v)
    length(dof_range) == n_base_funcs || throw_incompatible_dof_length(length(dof_range), n_base_funcs)
    @boundscheck checkbounds(u, dof_range)
    @boundscheck checkquadpoint(fe_v, q_point)
    grad = function_gradient_init(fe_v, u)
    @inbounds for (i, j) in pairs(dof_range)
        grad += shape_gradient(fe_v, q_point, i) * u[j]
    end
    return grad
end

# TODO: Deprecate this, nobody is using this in practice...
function function_gradient(fe_v::AbstractValues, q_point::Int, u::AbstractVector{<:Vec})
    n_base_funcs = getnbasefunctions(fe_v)
    length(u) == n_base_funcs || throw_incompatible_dof_length(length(u), n_base_funcs)
    @boundscheck checkquadpoint(fe_v, q_point)
    grad = function_gradient_init(fe_v, u)
    @inbounds for i in 1:n_base_funcs
        grad += u[i] ⊗ shape_gradient(fe_v, q_point, i)
    end
    return grad
end

"""
    shape_gradient_type(fe_v::AbstractValues)

Return the type of `shape_gradient(fe_v, q_point, base_function)`
"""
function shape_gradient_type(fe_v::AbstractValues)
    # Default fallback
    return typeof(shape_gradient(fe_v, 1, 1))
end

function function_gradient_init(cv::AbstractValues, ::AbstractVector{T}) where {T}
    return zero(shape_gradient_type(cv)) * zero(T)
end
function function_gradient_init(cv::AbstractValues, ::AbstractVector{T}) where {T <: AbstractVector}
    return zero(T) ⊗ zero(shape_gradient_type(cv))
end

"""
    function_hessian(fe_v::AbstractValues{dim}, q_point::Int, u::AbstractVector{<:AbstractFloat}, [dof_range])

    Compute the hessian of the function in a quadrature point. `u` is a vector with values
    for the degrees of freedom.
"""
function function_hessian(fe_v::AbstractValues, q_point::Int, u::AbstractVector, dof_range = eachindex(u))
    n_base_funcs = getnbasefunctions(fe_v)
    length(dof_range) == n_base_funcs || throw_incompatible_dof_length(length(dof_range), n_base_funcs)
    @boundscheck checkbounds(u, dof_range)
    @boundscheck checkquadpoint(fe_v, q_point)
    hess = function_hessian_init(fe_v, u)
    @inbounds for (i, j) in pairs(dof_range)
        hess += shape_hessian(fe_v, q_point, i) * u[j]
    end
    return hess
end

"""
    shape_hessian_type(fe_v::AbstractValues)

Return the type of `shape_hessian(fe_v, q_point, base_function)`
"""
function shape_hessian_type(fe_v::AbstractValues)
    # Default fallback
    return typeof(shape_hessian(fe_v, 1, 1))
end

function function_hessian_init(cv::AbstractValues, ::AbstractVector{T}) where {T}
    return zero(shape_hessian_type(cv)) * zero(T)
end

"""
    function_symmetric_gradient(fe_v::AbstractValues, q_point::Int, u::AbstractVector, [dof_range])

Compute the symmetric gradient of the function, see [`function_gradient`](@ref).
Return a `SymmetricTensor`.

The symmetric gradient of a scalar function is computed as
``\\left[ \\mathbf{\\nabla}  \\mathbf{u}(\\mathbf{x_q}) \\right]^\\text{sym} =  \\sum\\limits_{i = 1}^n  \\frac{1}{2} \\left[ \\mathbf{\\nabla} N_i (\\mathbf{x}_q) \\otimes \\mathbf{u}_i + \\mathbf{u}_i  \\otimes  \\mathbf{\\nabla} N_i (\\mathbf{x}_q) \\right]``
where ``\\mathbf{u}_i`` are the nodal values of the function.
"""
function function_symmetric_gradient(fe_v::AbstractValues, q_point::Int, u::AbstractVector, dof_range)
    grad = function_gradient(fe_v, q_point, u, dof_range)
    return symmetric(grad)
end

function function_symmetric_gradient(fe_v::AbstractValues, q_point::Int, u::AbstractVector)
    grad = function_gradient(fe_v, q_point, u)
    return symmetric(grad)
end
"""
    function_divergence(fe_v::AbstractValues, q_point::Int, u::AbstractVector, [dof_range])

Compute the divergence of the vector valued function in a quadrature point.

The divergence of a vector valued functions in the quadrature point ``\\mathbf{x}_q)`` is computed as
``\\mathbf{\\nabla} \\cdot \\mathbf{u}(\\mathbf{x_q}) = \\sum\\limits_{i = 1}^n \\mathbf{\\nabla} N_i (\\mathbf{x_q}) \\cdot \\mathbf{u}_i``
where ``\\mathbf{u}_i`` are the nodal values of the function.
"""
function function_divergence(fe_v::AbstractValues, q_point::Int, u::AbstractVector, dof_range = eachindex(u))
    return divergence_from_gradient(function_gradient(fe_v, q_point, u, dof_range))
end

# TODO: Deprecate this, nobody is using this in practice...
function function_divergence(fe_v::AbstractValues, q_point::Int, u::AbstractVector{<:Vec})
    n_base_funcs = getnbasefunctions(fe_v)
    length(u) == n_base_funcs || throw_incompatible_dof_length(length(u), n_base_funcs)
    @boundscheck checkquadpoint(fe_v, q_point)
    diverg = zero(eltype(eltype(u)))
    @inbounds for i in 1:n_base_funcs
        diverg += shape_gradient(fe_v, q_point, i) ⋅ u[i]
    end
    return diverg
end

"""
    function_curl(fe_v::AbstractValues, q_point::Int, u::AbstractVector, [dof_range])

Compute the curl of the vector valued function in a quadrature point.

The curl of a vector valued functions in the quadrature point ``\\mathbf{x}_q)`` is computed as
``\\mathbf{\\nabla} \\times \\mathbf{u}(\\mathbf{x_q}) = \\sum\\limits_{i = 1}^n \\mathbf{\\nabla} N_i \\times (\\mathbf{x_q}) \\cdot \\mathbf{u}_i``
where ``\\mathbf{u}_i`` are the nodal values of the function.
"""
function_curl(fe_v::AbstractValues, q_point::Int, u::AbstractVector, dof_range = eachindex(u)) =
    curl_from_gradient(function_gradient(fe_v, q_point, u, dof_range))

# TODO: Deprecate this, nobody is using this in practice...
function_curl(fe_v::AbstractValues, q_point::Int, u::AbstractVector{<:Vec}) =
    curl_from_gradient(function_gradient(fe_v, q_point, u))

"""
    spatial_coordinate(fe_v::AbstractValues, q_point::Int, x::AbstractVector)

Compute the spatial coordinate in a quadrature point. `x` contains the nodal
coordinates of the cell.

The coordinate is computed, using the geometric interpolation, as
``\\mathbf{x} = \\sum\\limits_{i = 1}^n M_i (\\mathbf{\\xi}) \\mathbf{\\hat{x}}_i``.

where ``\\xi``is the coordinate of the given quadrature point `q_point` of the associated
quadrature rule.
"""
function spatial_coordinate(fe_v::AbstractValues, q_point::Int, x::AbstractVector{<:Vec})
    n_base_funcs = getngeobasefunctions(fe_v)
    length(x) == n_base_funcs || throw_incompatible_coord_length(length(x), n_base_funcs)
    @boundscheck checkquadpoint(fe_v, q_point)
    vec = zero(eltype(x))
    @inbounds for i in 1:n_base_funcs
        vec += geometric_value(fe_v, q_point, i) * x[i]
    end
    return vec
end

"""
    spatial_coordinate(ip::ScalarInterpolation, ξ::Vec, x::AbstractVector{<:Vec{sdim, T}})

Compute the spatial coordinate in a given quadrature point. `x` contains the nodal coordinates of the cell.

The coordinate is computed, using the geometric interpolation, as
``\\mathbf{x} = \\sum\\limits_{i = 1}^n M_i (\\mathbf{\\xi}) \\mathbf{\\hat{x}}_i``
"""
function spatial_coordinate(interpolation::ScalarInterpolation, ξ::Vec, x::AbstractVector{<:Vec})
    n_basefuncs = getnbasefunctions(interpolation)
    @boundscheck checkbounds(x, Base.OneTo(n_basefuncs))
    vec = zero(eltype(x))
    @inbounds for j in 1:n_basefuncs
        M = reference_shape_value(interpolation, ξ, j)
        vec += M * x[j]
    end
    return vec
end

# Utility functions used by GeometryMapping, FunctionValues
_copy_or_nothing(x) = copy(x)
_copy_or_nothing(::Nothing) = nothing

function reference_shape_values!(values::AbstractMatrix, ip, qr_points::AbstractVector{<:Vec})
    for (qp, ξ) in pairs(qr_points)
        reference_shape_values!(@view(values[:, qp]), ip, ξ)
    end
    return
end

function reference_shape_gradients_and_values!(gradients::AbstractMatrix, values::AbstractMatrix, ip, qr_points::AbstractVector{<:Vec})
    for (qp, ξ) in pairs(qr_points)
        reference_shape_gradients_and_values!(@view(gradients[:, qp]), @view(values[:, qp]), ip, ξ)
    end
    return
end

function reference_shape_hessians_gradients_and_values!(hessians::AbstractMatrix, gradients::AbstractMatrix, values::AbstractMatrix, ip, qr_points::AbstractVector{<:Vec})
    for (qp, ξ) in pairs(qr_points)
        reference_shape_hessians_gradients_and_values!(@view(hessians[:, qp]), @view(gradients[:, qp]), @view(values[:, qp]), ip, ξ)
    end
    return
end

assert_same_refshapes(::Union{QuadratureRule{RS}, FacetQuadratureRule{RS}}, ::Interpolation{RS}, ::Interpolation{RS}) where {RS} = nothing
function assert_same_refshapes(qr::Union{QuadratureRule, FacetQuadratureRule}, ipf::Interpolation, ipg::Interpolation)
    throw(
        ArgumentError(
            """
            The reference shapes of the quadrature rule ($(getrefshape(qr))),
            function interpolation ($(getrefshape(ipf))), and geometric interpolation ($(getrefshape(ipg))),
            must be equal.
            """
        )
    )
end
