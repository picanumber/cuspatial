/*
 * Copyright (c) 2022, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <type_traits>

namespace cuspatial {
namespace detail {

/**
 * @internal
 * @brief returns true if all types Ts... are the same as T.
 */
template <typename T, typename... Ts>
constexpr bool is_same()
{
  return std::conjunction_v<std::is_same<T, Ts>...>;
}

/**
 * @internal
 * @brief returns true if all types Ts... are convertible to U.
 */
template <typename U, typename... Ts>
constexpr bool is_convertible_to()
{
  return std::conjunction_v<std::is_convertible<Ts, U>...>;
}

/**
 * @internal
 * @brief returns true if all types Ts... are floating point types.
 */
template <typename... Ts>
constexpr bool is_floating_point()
{
  return std::conjunction_v<std::is_floating_point<Ts>...>;
}

/**
 * @internal
 * @brief returns true if all types are floating point types.
 */
template <typename... Ts>
constexpr bool is_integral()
{
  return std::conjunction_v<std::is_integral<Ts>...>;
}

/**
 * @internal
 * @brief returns true if T and all types Ts... are the same floating point type.
 */
template <typename T, typename... Ts>
constexpr bool is_same_floating_point()
{
  return std::conjunction_v<std::is_same<T, Ts>...> and
         std::conjunction_v<std::is_floating_point<Ts>...>;
}

/**
 * @internal
 * @brief Get the value type of @p Iterator type
 *
 * @tparam Iterator The iterator type to get from
 */
template <typename Iterator>
using iterator_value_type = typename std::iterator_traits<Iterator>::value_type;

/**
 * @internal
 * @brief Get the value type of the underlying vec_2d type from @p Iterator type
 *
 * @tparam Iterator The value type to get from, must point to a cuspatial::vec_2d
 */
template <typename Iterator>
using iterator_vec_base_type = typename iterator_value_type<Iterator>::value_type;

}  // namespace detail
}  // namespace cuspatial
