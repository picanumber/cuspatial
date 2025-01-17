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

#include <cuspatial/error.hpp>
#include <cuspatial/experimental/point_in_polygon.cuh>
#include <cuspatial/experimental/type_utils.hpp>
#include <cuspatial/vec_2d.hpp>

#include <rmm/device_vector.hpp>

#include <thrust/host_vector.h>
#include <thrust/iterator/counting_iterator.h>
#include <thrust/iterator/transform_iterator.h>

#include <gtest/gtest.h>

using namespace cuspatial;

template <typename T>
struct PointInPolygonTest : public ::testing::Test {
 public:
  rmm::device_vector<cartesian_2d<T>> make_device_points(std::initializer_list<cartesian_2d<T>> pts)
  {
    return rmm::device_vector<cartesian_2d<T>>(pts.begin(), pts.end());
  }

  rmm::device_vector<std::size_t> make_device_offsets(std::initializer_list<std::size_t> pts)
  {
    return rmm::device_vector<std::size_t>(pts.begin(), pts.end());
  }
};

// float and double are logically the same but would require separate tests due to precision.
using TestTypes = ::testing::Types<float, double>;
TYPED_TEST_CASE(PointInPolygonTest, TestTypes);

TYPED_TEST(PointInPolygonTest, OnePolygonOneRing)
{
  auto test_point        = this->make_device_points({{-2.0, 0.0},
                                              {2.0, 0.0},
                                              {0.0, -2.0},
                                              {0.0, 2.0},
                                              {-0.5, 0.0},
                                              {0.5, 0.0},
                                              {0.0, -0.5},
                                              {0.0, 0.5}});
  auto poly_offsets      = this->make_device_offsets({0});
  auto poly_ring_offsets = this->make_device_offsets({0});
  auto poly_point =
    this->make_device_points({{-1.0, -1.0}, {1.0, -1.0}, {1.0, 1.0}, {-1.0, 1.0}, {-1.0, -1.0}});

  auto got      = rmm::device_vector<int32_t>(test_point.size());
  auto expected = std::vector<int32_t>{false, false, false, false, true, true, true, true};

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              poly_offsets.begin(),
                              poly_offsets.end(),
                              poly_ring_offsets.begin(),
                              poly_ring_offsets.end(),
                              poly_point.begin(),
                              poly_point.end(),
                              got.begin());

  EXPECT_EQ(got, expected);
  EXPECT_EQ(ret, got.end());
}

TYPED_TEST(PointInPolygonTest, TwoPolygonsOneRingEach)
{
  auto test_point = this->make_device_points({{-2.0, 0.0},
                                              {2.0, 0.0},
                                              {0.0, -2.0},
                                              {0.0, 2.0},
                                              {-0.5, 0.0},
                                              {0.5, 0.0},
                                              {0.0, -0.5},
                                              {0.0, 0.5}});

  auto poly_offsets      = this->make_device_offsets({0, 1});
  auto poly_ring_offsets = this->make_device_offsets({0, 5});
  auto poly_point        = this->make_device_points({{-1.0, -1.0},
                                              {-1.0, 1.0},
                                              {1.0, 1.0},
                                              {1.0, -1.0},
                                              {-1.0, -1.0},
                                              {0.0, 1.0},
                                              {1.0, 0.0},
                                              {0.0, -1.0},
                                              {-1.0, 0.0},
                                              {0.0, 1.0}});

  auto got      = rmm::device_vector<int32_t>(test_point.size());
  auto expected = std::vector<int32_t>({0b00, 0b00, 0b00, 0b00, 0b11, 0b11, 0b11, 0b11});

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              poly_offsets.begin(),
                              poly_offsets.end(),
                              poly_ring_offsets.begin(),
                              poly_ring_offsets.end(),
                              poly_point.begin(),
                              poly_point.end(),
                              got.begin());

  EXPECT_EQ(got, expected);
  EXPECT_EQ(ret, got.end());
}

TYPED_TEST(PointInPolygonTest, OnePolygonTwoRings)
{
  auto test_point =
    this->make_device_points({{0.0, 0.0}, {-0.4, 0.0}, {-0.6, 0.0}, {0.0, 0.4}, {0.0, -0.6}});
  auto poly_offsets      = this->make_device_offsets({0});
  auto poly_ring_offsets = this->make_device_offsets({0, 5});
  auto poly_point        = this->make_device_points({{-1.0, -1.0},
                                              {1.0, -1.0},
                                              {1.0, 1.0},
                                              {-1.0, 1.0},
                                              {-1.0, -1.0},
                                              {-0.5, -0.5},
                                              {-0.5, 0.5},
                                              {0.5, 0.5},
                                              {0.5, -0.5},
                                              {-0.5, -0.5}});

  auto got      = rmm::device_vector<int32_t>(test_point.size());
  auto expected = std::vector<int32_t>{0b0, 0b0, 0b1, 0b0, 0b1};

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              poly_offsets.begin(),
                              poly_offsets.end(),
                              poly_ring_offsets.begin(),
                              poly_ring_offsets.end(),
                              poly_point.begin(),
                              poly_point.end(),
                              got.begin());

  EXPECT_EQ(got, expected);
  EXPECT_EQ(ret, got.end());
}

TYPED_TEST(PointInPolygonTest, EdgesOfSquare)
{
  auto test_point        = this->make_device_points({{0.0, 0.0}});
  auto poly_offsets      = this->make_device_offsets({0, 1, 2, 3});
  auto poly_ring_offsets = this->make_device_offsets({0, 5, 10, 15});

  // 0: rect on min x side
  // 1: rect on max x side
  // 2: rect on min y side
  // 3: rect on max y side
  auto poly_point = this->make_device_points(
    {{-1.0, -1.0}, {0.0, -1.0}, {0.0, 1.0},  {-1.0, 1.0},  {-1.0, -1.0}, {0.0, -1.0}, {1.0, -1.0},
     {1.0, 1.0},   {0.0, 1.0},  {0.0, -1.0}, {-1.0, -1.0}, {-1.0, 0.0},  {1.0, 0.0},  {1.0, -1.0},
     {-1.0, 1.0},  {-1.0, 0.0}, {-1.0, 1.0}, {1.0, 1.0},   {1.0, 0.0},   {-1.0, 0.0}});

  // point is included in rects on min x and y sides, but not on max x or y sides.
  // this behavior is inconsistent, and not necessarily intentional.
  auto expected = std::vector<int32_t>{0b1010};
  auto got      = rmm::device_vector<int32_t>(test_point.size());

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              poly_offsets.begin(),
                              poly_offsets.end(),
                              poly_ring_offsets.begin(),
                              poly_ring_offsets.end(),
                              poly_point.begin(),
                              poly_point.end(),
                              got.begin());

  EXPECT_EQ(got, expected);
  EXPECT_EQ(ret, got.end());
}

TYPED_TEST(PointInPolygonTest, CornersOfSquare)
{
  auto test_point        = this->make_device_points({{0.0, 0.0}});
  auto poly_offsets      = this->make_device_offsets({0, 1, 2, 3});
  auto poly_ring_offsets = this->make_device_offsets({0, 5, 10, 15});

  // 0: min x min y corner
  // 1: min x max y corner
  // 2: max x min y corner
  // 3: max x max y corner
  auto poly_point = this->make_device_points(
    {{-1.0, -1.0}, {-1.0, 0.0}, {0.0, 0.0},  {0.0, -1.0}, {-1.0, -1.0}, {-1.0, 0.0}, {-1.0, 1.0},
     {0.0, 1.0},   {-1.0, 0.0}, {-1.0, 0.0}, {0.0, -1.0}, {0.0, 0.0},   {1.0, 0.0},  {1.0, -1.0},
     {0.0, -1.0},  {0.0, 0.0},  {0.0, 1.0},  {1.0, 1.0},  {1.0, 0.0},   {0.0, 0.0}});

  // point is only included on the max x max y corner.
  // this behavior is inconsistent, and not necessarily intentional.
  auto expected = std::vector<int32_t>{0b1000};
  auto got      = rmm::device_vector<int32_t>(test_point.size());

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              poly_offsets.begin(),
                              poly_offsets.end(),
                              poly_ring_offsets.begin(),
                              poly_ring_offsets.end(),
                              poly_point.begin(),
                              poly_point.end(),
                              got.begin());

  EXPECT_EQ(got, expected);
  EXPECT_EQ(ret, got.end());
}

struct OffsetIteratorFunctor {
  std::size_t __device__ operator()(std::size_t idx) { return idx * 5; }
};

template <typename T>
struct PolyPointIteratorFunctorA {
  T __device__ operator()(std::size_t idx)
  {
    switch (idx % 5) {
      case 0:
      case 1: return -1.0;
      case 2:
      case 3: return 1.0;
      case 4:
      default: return -1.0;
    }
  }
};

template <typename T>
struct PolyPointIteratorFunctorB {
  T __device__ operator()(std::size_t idx)
  {
    switch (idx % 5) {
      case 0: return -1.0;
      case 1:
      case 2: return 1.0;
      case 3:
      case 4:
      default: return -1.0;
    }
  }
};

TYPED_TEST(PointInPolygonTest, 31PolygonSupport)
{
  using T = TypeParam;

  auto constexpr num_polys       = 31;
  auto constexpr num_poly_points = num_polys * 5;

  auto test_point   = this->make_device_points({{0.0, 0.0}, {2.0, 0.0}});
  auto offsets_iter = thrust::make_counting_iterator<std::size_t>(0);
  auto poly_ring_offsets_iter =
    thrust::make_transform_iterator(offsets_iter, OffsetIteratorFunctor{});
  auto poly_point_xs_iter =
    thrust::make_transform_iterator(offsets_iter, PolyPointIteratorFunctorA<T>{});
  auto poly_point_ys_iter =
    thrust::make_transform_iterator(offsets_iter, PolyPointIteratorFunctorB<T>{});
  auto poly_point_iter = make_cartesian_2d_iterator(poly_point_xs_iter, poly_point_ys_iter);

  auto expected =
    std::vector<int32_t>({0b1111111111111111111111111111111, 0b0000000000000000000000000000000});
  auto got = rmm::device_vector<int32_t>(test_point.size());

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              offsets_iter,
                              offsets_iter + num_polys,
                              poly_ring_offsets_iter,
                              poly_ring_offsets_iter + num_polys,
                              poly_point_iter,
                              poly_point_iter + num_poly_points,
                              got.begin());

  EXPECT_EQ(got, expected);
  EXPECT_EQ(ret, got.end());
}

struct PointInPolygonErrorTest : public PointInPolygonTest<double> {
};

TEST_F(PointInPolygonErrorTest, MismatchPolyPointXYLength)
{
  using T = double;

  auto test_point        = this->make_device_points({{0.0, 0.0}, {0.0, 0.0}});
  auto poly_offsets      = this->make_device_offsets({0});
  auto poly_ring_offsets = this->make_device_offsets({0});
  auto poly_point        = this->make_device_points({{0.0, 1.0}, {1.0, 0.0}, {0.0, -1.0}});
  auto got               = rmm::device_vector<int32_t>(test_point.size());

  EXPECT_THROW(point_in_polygon(test_point.begin(),
                                test_point.end(),
                                poly_offsets.begin(),
                                poly_offsets.end(),
                                poly_ring_offsets.begin(),
                                poly_ring_offsets.end(),
                                poly_point.begin(),
                                poly_point.end(),
                                got.begin()),
               cuspatial::logic_error);
}

TYPED_TEST(PointInPolygonTest, SelfClosingLoopLeftEdgeMissing)
{
  using T                = TypeParam;
  auto test_point        = this->make_device_points({{-2.0, 0.0}, {0.0, 0.0}, {2.0, 0.0}});
  auto poly_offsets      = this->make_device_offsets({0});
  auto poly_ring_offsets = this->make_device_offsets({0});
  // "left" edge missing
  auto poly_point = this->make_device_points({{-1, 1}, {1, 1}, {1, -1}, {-1, -1}});
  auto expected   = std::vector<int32_t>{0b0, 0b1, 0b0};
  auto got        = rmm::device_vector<int32_t>(test_point.size());

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              poly_offsets.begin(),
                              poly_offsets.end(),
                              poly_ring_offsets.begin(),
                              poly_ring_offsets.end(),
                              poly_point.begin(),
                              poly_point.end(),
                              got.begin());

  EXPECT_EQ(expected, got);
  EXPECT_EQ(got.end(), ret);
}

TYPED_TEST(PointInPolygonTest, SelfClosingLoopRightEdgeMissing)
{
  using T                = TypeParam;
  auto test_point        = this->make_device_points({{-2.0, 0.0}, {0.0, 0.0}, {2.0, 0.0}});
  auto poly_offsets      = this->make_device_offsets({0});
  auto poly_ring_offsets = this->make_device_offsets({0});
  // "right" edge missing
  auto poly_point = this->make_device_points({{1, -1}, {-1, -1}, {-1, 1}, {1, 1}});
  auto expected   = std::vector<int32_t>{0b0, 0b1, 0b0};
  auto got        = rmm::device_vector<int32_t>(test_point.size());

  auto ret = point_in_polygon(test_point.begin(),
                              test_point.end(),
                              poly_offsets.begin(),
                              poly_offsets.end(),
                              poly_ring_offsets.begin(),
                              poly_ring_offsets.end(),
                              poly_point.begin(),
                              poly_point.end(),
                              got.begin());

  EXPECT_EQ(expected, got);
  EXPECT_EQ(got.end(), ret);
}
