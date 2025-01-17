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

#include <benchmarks/fixture/rmm_pool_raii.hpp>
#include <nvbench/nvbench.cuh>

#include <cuspatial/experimental/point_in_polygon.cuh>
#include <cuspatial/vec_2d.hpp>

#include <rmm/device_vector.hpp>
#include <rmm/exec_policy.hpp>

#include <thrust/iterator/counting_iterator.h>

#include <memory>
#include <numeric>

using namespace cuspatial;

constexpr double PI                  = 3.141592653589793;
auto constexpr radius                = 10.0;
auto constexpr num_polygons          = 31;
auto constexpr num_rings_per_polygon = 1;  // only 1 ring for now

/**
 * @brief Generate a random point within a window of [minXY, maxXY]
 */
template <typename T>
cartesian_2d<T> random_point(cartesian_2d<T> minXY, cartesian_2d<T> maxXY)
{
  auto x = minXY.x + (maxXY.x - minXY.x) * rand() / static_cast<T>(RAND_MAX);
  auto y = minXY.y + (maxXY.y - minXY.y) * rand() / static_cast<T>(RAND_MAX);
  return cartesian_2d<T>{x, y};
}

/**
 * @brief Helper to generate 31 simple polygons used for benchmarks.
 *
 * The polygons are generated by setting a centroid and a radius. The vertices of the
 * polygons are generated by rotating a circle around the centroid. The centroid of
 * the polygon is randomly sampled from window [minXY, maxXY].
 *
 * @tparam T The floating point type for the coordinates
 * @param num_sides Number of sides of the polygon
 * @param radius The radius of the circle from which the vertices are sampled
 * @param minXY The minimum xy coordinates of the window from which the centroid is sampled
 * @param maxXY The maximum xy coordinates of the window from which the centroid is sampled
 * @return 32 polygons in structure of arrays:
 *      [polygon offset, poly ring offset, point coordinates]
 *
 */
template <typename T>
std::tuple<rmm::device_vector<int32_t>,
           rmm::device_vector<int32_t>,
           rmm::device_vector<cartesian_2d<T>>>
generate_polygon(int32_t num_sides, T radius, cartesian_2d<T> minXY, cartesian_2d<T> maxXY)
{
  std::vector<int32_t> polygon_offsets(num_polygons);
  std::vector<int32_t> ring_offsets(num_polygons * num_rings_per_polygon);
  std::vector<cartesian_2d<T>> polygon_points(31 * (num_sides + 1));

  std::iota(polygon_offsets.begin(), polygon_offsets.end(), 0);
  std::iota(ring_offsets.begin(), ring_offsets.end(), 0);
  std::transform(
    ring_offsets.begin(), ring_offsets.end(), ring_offsets.begin(), [num_sides](int32_t i) {
      return i * (num_sides + 1);
    });

  for (int32_t i = 0; i < num_polygons; i++) {
    auto it     = thrust::make_counting_iterator(0);
    auto begin  = i * num_sides + polygon_points.begin();
    auto center = random_point(minXY, maxXY);
    std::transform(it, it + num_sides + 1, begin, [num_sides, radius, center](int32_t j) {
      return cartesian_2d<T>{
        static_cast<T>(radius * std::cos(2 * PI * (j % num_sides) / static_cast<T>(num_sides)) +
                       center.x),
        static_cast<T>(radius * std::sin(2 * PI * (j % num_sides) / static_cast<T>(num_sides)) +
                       center.y)};
    });
  }

  // Implicitly convert to device_vector
  return std::make_tuple(polygon_offsets, ring_offsets, polygon_points);
}

/**
 * @brief Randomly generate `num_test_points` points within window `minXY` and `maxXY`
 *
 * @tparam T The floating point type for the coordinates
 */
template <typename T>
rmm::device_vector<cartesian_2d<T>> generate_points(int32_t num_test_points,
                                                    cartesian_2d<T> minXY,
                                                    cartesian_2d<T> maxXY)
{
  std::vector<cartesian_2d<T>> points(num_test_points);
  std::generate(
    points.begin(), points.end(), [minXY, maxXY]() { return random_point(minXY, maxXY); });
  // Implicitly convert to device_vector
  return points;
}

template <typename T>
void point_in_polygon_benchmark(nvbench::state& state, nvbench::type_list<T>)
{
  // TODO: to be replaced by nvbench fixture once it's ready
  cuspatial::rmm_pool_raii rmm_pool;

  std::srand(0);  // For reproducibility
  auto const minXY = cartesian_2d<T>{-radius * 2, -radius * 2};
  auto const maxXY = cartesian_2d<T>{radius * 2, radius * 2};

  auto const num_test_points{state.get_int64("NumTestPoints")},
    num_sides_per_ring{state.get_int64("NumSidesPerRing")};

  auto const num_rings = num_polygons * num_rings_per_polygon;
  auto const num_polygon_points =
    num_rings * (num_sides_per_ring + 1);  // +1 for the overlapping start and end point of the ring

  auto test_points = generate_points<T>(num_test_points, minXY, maxXY);
  auto [polygon_offsets, ring_offsets, polygon_points] =
    generate_polygon<T>(num_sides_per_ring, radius, minXY, maxXY);
  rmm::device_vector<int32_t> result(num_test_points);

  auto polygon_offsets_begin = polygon_offsets.begin();
  auto ring_offsets_begin    = ring_offsets.begin();
  auto polygon_points_begin  = polygon_points.begin();

  state.add_element_count(num_polygon_points, "NumPolygonPoints");
  state.add_global_memory_reads<T>(num_test_points * 2, "TotalMemoryReads");
  state.add_global_memory_reads<T>(num_polygon_points);
  state.add_global_memory_reads<int32_t>(num_rings);
  state.add_global_memory_reads<int32_t>(num_polygons);
  state.add_global_memory_writes<int32_t>(num_test_points, "TotalMemoryWrites");

  state.exec(nvbench::exec_tag::sync,
             [&test_points,
              polygon_offsets_begin,
              ring_offsets_begin,
              &num_rings,
              polygon_points_begin,
              &num_polygon_points,
              &result](nvbench::launch& launch) {
               point_in_polygon(test_points.begin(),
                                test_points.end(),
                                polygon_offsets_begin,
                                polygon_offsets_begin + num_polygons,
                                ring_offsets_begin,
                                ring_offsets_begin + num_rings,
                                polygon_points_begin,
                                polygon_points_begin + num_polygon_points,
                                result.begin());
             });
}

using floating_point_types = nvbench::type_list<float, double>;
NVBENCH_BENCH_TYPES(point_in_polygon_benchmark, NVBENCH_TYPE_AXES(floating_point_types))
  .set_type_axes_names({"CoordsType"})
  .add_int64_axis("NumTestPoints", {1'000, 100'000, 10'000'000})
  .add_int64_axis("NumSidesPerRing", {4, 10, 100});
