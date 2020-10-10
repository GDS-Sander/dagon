/*
Copyright (c) 2013-2020 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.ext.physics.geometry;

import std.math;

import dlib.core.ownership;
import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.math.utils;
import dlib.geometry.aabb;

import dagon.ext.physics.world;

enum GeomType
{
    Undefined,
    Sphere,
    Box,
    Cylinder,
    Cone,
    Ellipsoid,
    Triangle,
    UserDefined
}

abstract class Geometry: Owner
{
    GeomType type = GeomType.Undefined;

    this(Owner o)
    {
        super(o);
    }

    Vector3f supportPoint(Vector3f dir)
    {
        return Vector3f(0.0f, 0.0f, 0.0f);
    }

    Matrix3x3f inertiaTensor(float mass)
    {
        return Matrix3x3f.identity * mass;
    }

    AABB boundingBox(Vector3f position)
    {
        return AABB(position, Vector3f(1.0f, 1.0f, 1.0f));
    }
}

class GeomSphere: Geometry
{
    float radius;

    this(PhysicsWorld world, float r)
    {
        super(world);
        type = GeomType.Sphere;
        radius = r;
    }

    override Vector3f supportPoint(Vector3f dir)
    {
        return dir.normalized * radius;
    }

    override Matrix3x3f inertiaTensor(float mass)
    {
        float v = 0.4f * mass * radius * radius;

        return matrixf(
            v, 0, 0,
            0, v, 0,
            0, 0, v
        );
    }

    override AABB boundingBox(Vector3f position)
    {
        return AABB(position, Vector3f(radius, radius, radius));
    }
}

class GeomBox: Geometry
{
    Vector3f halfSize;
    float bsphereRadius;

    this(PhysicsWorld world, Vector3f hsize)
    {
        super(world);
        type = GeomType.Box;
        halfSize = hsize;
        bsphereRadius = halfSize.length;
    }

    override Vector3f supportPoint(Vector3f dir)
    {
        Vector3f result;
        result.x = sign(dir.x) * halfSize.x;
        result.y = sign(dir.y) * halfSize.y;
        result.z = sign(dir.z) * halfSize.z;
        return result;
    }

    override Matrix3x3f inertiaTensor(float mass)
    {
        float x2 = halfSize.x * halfSize.x;
        float y2 = halfSize.y * halfSize.y;
        float z2 = halfSize.z * halfSize.z;

        return matrixf(
            (y2 + z2)/3 * mass, 0, 0,
            0, (x2 + z2)/3 * mass, 0,
            0, 0, (x2 + y2)/3 * mass
        );
    }

    override AABB boundingBox(Vector3f position)
    {
        return AABB(position,
            Vector3f(bsphereRadius, bsphereRadius, bsphereRadius));
    }
}

class GeomCylinder: Geometry
{
    float height;
    float radius;

    this(PhysicsWorld world, float h, float r)
    {
        super(world);
        type = GeomType.Cylinder;
        height = h;
        radius = r;
    }

    override Vector3f supportPoint(Vector3f dir)
    {
        Vector3f result;
        float sigma = sqrt((dir.x * dir.x + dir.z * dir.z));

        if (sigma > 0.0f)
        {
            result.x = dir.x / sigma * radius;
            result.y = sign(dir.y) * height * 0.5f;
            result.z = dir.z / sigma * radius;
        }
        else
        {
            result.x = 0.0f;
            result.y = sign(dir.y) * height * 0.5f;
            result.z = 0.0f;
        }

        return result;
    }

    override Matrix3x3f inertiaTensor(float mass)
    {
        float r2 = radius * radius;
        float h2 = height * height;

        return matrixf(
            (3*r2 + h2)/12 * mass, 0, 0,
            0, (3*r2 + h2)/12 * mass, 0,
            0, 0, r2/2 * mass
        );
    }

    override AABB boundingBox(Vector3f position)
    {
        float rsum = radius + radius;
        float d = sqrt(rsum * rsum + height * height) * 0.5f;
        return AABB(position, Vector3f(d, d, d));
    }
}

class GeomCone: Geometry
{
    float radius;
    float height;

    this(PhysicsWorld world, float h, float r)
    {
        super(world);
        type = GeomType.Cone;
        height = h;
        radius = r;
    }

    override Vector3f supportPoint(Vector3f dir)
    {
        float zdist = dir[0] * dir[0] + dir[1] * dir[1];
        float len = zdist + dir[2] * dir[2];
        zdist = sqrt(zdist);
        len = sqrt(len);
        float half_h = height * 0.5;
        float radius = radius;

        float sin_a = radius / sqrt(radius * radius + 4.0f * half_h * half_h);

        if (dir[2] > len * sin_a)
            return Vector3f(0.0f, 0.0f, half_h);
        else if (zdist > 0.0f)
        {
            float rad = radius / zdist;
            return Vector3f(rad * dir[0], rad * dir[1], -half_h);
        }
        else
            return Vector3f(0.0f, 0.0f, -half_h);
    }

    override Matrix3x3f inertiaTensor(float mass)
    {
        float r2 = radius * radius;
        float h2 = height * height;

        return matrixf(
            (3.0f/80.0f*h2 + 3.0f/20.0f*r2) * mass, 0, 0,
            0, (3.0f/80.0f*h2 + 3.0f/20.0f*r2) * mass, 0,
            0, 0, (3.0f/10.0f*r2) * mass
        );
    }

    override AABB boundingBox(Vector3f position)
    {
        float rsum = radius + radius;
        float d = sqrt(rsum * rsum + height * height) * 0.5f;
        return AABB(position, Vector3f(d, d, d));
    }
}

class GeomEllipsoid: Geometry
{
    Vector3f radii;

    this(PhysicsWorld world, Vector3f r)
    {
        super(world);
        type = GeomType.Ellipsoid;
        radii = r;
    }

    override Vector3f supportPoint(Vector3f dir)
    {
        return dir.normalized * radii;
    }

    override Matrix3x3f inertiaTensor(float mass)
    {
        float x2 = radii.x * radii.x;
        float y2 = radii.y * radii.y;
        float z2 = radii.z * radii.z;

        return matrixf(
            (y2 + z2)/5 * mass, 0, 0,
            0, (x2 + z2)/5 * mass, 0,
            0, 0, (x2 + y2)/5 * mass
        );
    }

    override AABB boundingBox(Vector3f position)
    {
        return AABB(position, radii);
    }
}

class GeomTriangle: Geometry
{
    Vector3f[3] v;

    this(PhysicsWorld world, Vector3f a, Vector3f b, Vector3f c)
    {
        super(world);
        type = GeomType.Triangle;
        v[0] = a;
        v[1] = b;
        v[2] = c;
    }

    override Vector3f supportPoint(Vector3f dir)
    {
        float dota = dir.dot(v[0]);
        float dotb = dir.dot(v[1]);
        float dotc = dir.dot(v[2]);

        if (dota > dotb)
        {
            if (dotc > dota)
                return v[2];
            else
                return v[0];
        }
        else
        {
            if (dotc > dotb)
                return v[2];
            else
                return v[1];
        }
    }

    // TODO: boundingBox
}
