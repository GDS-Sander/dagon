/*
Copyright (c) 2014-2020 Timur Gafarov

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

module dagon.ext.physics.shape;

import dlib.core.ownership;
import dlib.core.memory;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.transformation;
import dlib.geometry.aabb;
import dlib.geometry.sphere;

import dagon.ext.physics.world;
import dagon.ext.physics.geometry;

/*
 * ShapeComponent is a proxy object between RigidBody and Geometry.
 * It stores non-geometric information such as mass contribution,
 * position in body space and a unique identifier for indexing in
 * contact cache.
 * One Geometry can be shared between multiple ShapeComponents.
 */

class ShapeComponent: Owner
{
    Geometry geometry; // geometry
    Vector3f centroid; // position in body space
    float mass;        // mass contribution
    uint id = 0;       // global identifier

    Matrix4x4f _transformation;

    bool locked = false;

    bool active = true;
    bool solve = true;
    bool raycastable = true;
    int numCollisions = 0;

    @property
    {
        Matrix4x4f transformation()
        {
            while(locked) {}
            return _transformation;
        }

        void transformation(Matrix4x4f m)
        {
            locked = true;
            _transformation = m;
            locked = false;
        }
    }

    this(PhysicsWorld world, Geometry g, Vector3f c, float m)
    {
        super(world);

        geometry = g;
        centroid = c;
        mass = m;

        _transformation = Matrix4x4f.identity;
    }

    // position in world space
    @property Vector3f position()
    {
        return _transformation.translation;
    }

    @property AABB boundingBox()
    {
        return geometry.boundingBox(
            _transformation.translation);
    }

    @property Sphere boundingSphere()
    {
        AABB aabb = geometry.boundingBox(
            _transformation.translation);
        return Sphere(aabb.center, aabb.size.length);
    }

    Vector3f supportPointGlobal(Vector3f dir)
    {
        Vector3f result;
        Matrix4x4f* m = &_transformation;

        result.x = ((dir.x * m.a11) + (dir.y * m.a21)) + (dir.z * m.a31);
        result.y = ((dir.x * m.a12) + (dir.y * m.a22)) + (dir.z * m.a32);
        result.z = ((dir.x * m.a13) + (dir.y * m.a23)) + (dir.z * m.a33);

        result = geometry.supportPoint(result);

        float x = ((result.x * m.a11) + (result.y * m.a12)) + (result.z * m.a13);
        float y = ((result.x * m.a21) + (result.y * m.a22)) + (result.z * m.a23);
        float z = ((result.x * m.a31) + (result.y * m.a32)) + (result.z * m.a33);

        result.x = m.a14 + x;
        result.y = m.a24 + y;
        result.z = m.a34 + z;

        return result;
    }
}
