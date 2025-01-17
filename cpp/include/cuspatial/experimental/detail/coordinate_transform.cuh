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

#include <cuspatial/constants.hpp>
#include <cuspatial/vec_2d.hpp>

#include <rmm/cuda_stream_view.hpp>
#include <rmm/exec_policy.hpp>

#include <thrust/transform.h>

#include <iterator>
#include <type_traits>

namespace cuspatial {

namespace detail {

constexpr double EARTH_CIRCUMFERENCE_KM_PER_DEGREE = EARTH_CIRCUMFERENCE_EQUATOR_KM / 360.0;

template <typename T>
__device__ inline T midpoint(T a, T b)
{
  return (a + b) / 2;
}

template <typename T>
__device__ inline T lon_to_x(T lon, T lat)
{
  return lon * EARTH_CIRCUMFERENCE_KM_PER_DEGREE * cos(lat * DEGREE_TO_RADIAN);
};

template <typename T>
__device__ inline T lat_to_y(T lat)
{
  return lat * EARTH_CIRCUMFERENCE_KM_PER_DEGREE;
};

template <typename T>
struct to_cartesian_functor {
  to_cartesian_functor(lonlat_2d<T> origin) : _origin(origin) {}

  cartesian_2d<T> __device__ operator()(lonlat_2d<T> loc)
  {
    return cartesian_2d<T>{lon_to_x(_origin.x - loc.x, midpoint(loc.y, _origin.y)),
                           lat_to_y(_origin.y - loc.y)};
  }

 private:
  lonlat_2d<T> _origin{};
};

}  // namespace detail

template <class InputIt, class OutputIt, class T>
OutputIt lonlat_to_cartesian(InputIt lon_lat_first,
                             InputIt lon_lat_last,
                             OutputIt xy_first,
                             lonlat_2d<T> origin,
                             rmm::cuda_stream_view stream)
{
  static_assert(std::is_floating_point_v<T>,
                "lonlat_to_cartesian supports only floating-point coordinates.");

  CUSPATIAL_EXPECTS(origin.x >= -180 && origin.x <= 180 && origin.y >= -90 && origin.y <= 90,
                    "origin must have valid longitude [-180, 180] and latitude [-90, 90]");

  return thrust::transform(rmm::exec_policy(stream),
                           lon_lat_first,
                           lon_lat_last,
                           xy_first,
                           detail::to_cartesian_functor{origin});
}

}  // namespace cuspatial
