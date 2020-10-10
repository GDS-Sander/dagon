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

module dagon.ext.physics.constraint;

import std.math;
import std.algorithm;

import dlib.core.ownership;
import dlib.core.memory;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;

import dagon.ext.physics.world;
import dagon.ext.physics.rigidbody;

abstract class Constraint: Owner
{
    RigidBody body1;
    RigidBody body2;

    this(Owner o)
    {
        super(o);
    }

    void prepare(double delta);
    void step();
}

/*
 * Keeps bodies at some fixed (or max/min) distance from each other.
 * Also works as a spring, if softness is set to a higher value.
 */
class DistanceConstraint: Constraint
{
    enum DistanceBehavior
    {
        LimitDistance,
        LimitMaximumDistance,
        LimitMinimumDistance,
    }

    Vector3f r1, r2;

    float biasFactor = 0.1f;
    float softness = 0.01f;
    float distance;

    DistanceBehavior behavior = DistanceBehavior.LimitDistance;

    this(Owner owner, RigidBody body1, RigidBody body2, float dist = 0.0f)
    {
        super(owner);

        this.body1 = body1;
        this.body2 = body2;

        if (dist > 0.0f)
            distance = dist;
        else
            distance = (body1.worldCenterOfMass - body2.worldCenterOfMass).length;
    }

    float effectiveMass = 0.0f;
    float accumulatedImpulse = 0.0f;
    float bias;
    float softnessOverDt;

    Vector3f[4] jacobian;

    bool skipConstraint = false;

    float myCounter = 0.0f;

    override void prepare(double dt)
    {
        r1 = Vector3f(0.0f, 0.0f, 0.0f);
        r2 = Vector3f(0.0f, 0.0f, 0.0f);

        Vector3f dp = body2.worldCenterOfMass - body1.worldCenterOfMass;

        float deltaLength = dp.length - distance;

        if (behavior == DistanceBehavior.LimitMaximumDistance && deltaLength <= 0.0f)
            skipConstraint = true;
        else if (behavior == DistanceBehavior.LimitMinimumDistance && deltaLength >= 0.0f)
            skipConstraint = true;
        else
        {
            skipConstraint = false;

            Vector3f n = dp;
            if (n.lengthsqr != 0.0f)
                n.normalize();

            jacobian[0] = -n;
            jacobian[1] = -cross(r1, n);
            jacobian[2] = n;
            jacobian[3] = cross(r2, n);

            effectiveMass =
                body1.invMass + body2.invMass
              + dot(jacobian[1] * body1.invInertiaTensor, jacobian[1])
              + dot(jacobian[3] * body2.invInertiaTensor, jacobian[3]);

            softnessOverDt = softness / dt;
            effectiveMass += softnessOverDt;

            if (effectiveMass != 0)
                effectiveMass = 1.0f / effectiveMass;

            bias = deltaLength * biasFactor * (1.0f / dt);

            if (body1.dynamic)
            {
                body1.linearVelocity +=  jacobian[0] * accumulatedImpulse * body1.invMass;
                body1.angularVelocity += jacobian[1] * accumulatedImpulse * body1.invInertiaTensor;
            }

            if (body2.dynamic)
            {
                body2.linearVelocity +=  jacobian[2] * accumulatedImpulse * body2.invMass;
                body2.angularVelocity += jacobian[3] * accumulatedImpulse * body2.invInertiaTensor;
            }
        }
    }

    override void step()
    {
        if (skipConstraint)
            return;

        float jv =
            dot(body1.linearVelocity,  jacobian[0])
          + dot(body1.angularVelocity, jacobian[1])
          + dot(body2.linearVelocity,  jacobian[2])
          + dot(body2.angularVelocity, jacobian[3]);

        float softnessScalar = accumulatedImpulse * softnessOverDt;

        float lambda = -effectiveMass * (jv + bias + softnessScalar);

        if (behavior == DistanceBehavior.LimitMinimumDistance)
        {
            float previousAccumulatedImpulse = accumulatedImpulse;
            accumulatedImpulse = max(accumulatedImpulse + lambda, 0);
            lambda = accumulatedImpulse - previousAccumulatedImpulse;
        }
        else if (behavior == DistanceBehavior.LimitMaximumDistance)
        {
            float previousAccumulatedImpulse = accumulatedImpulse;
            accumulatedImpulse = min(accumulatedImpulse + lambda, 0);
            lambda = accumulatedImpulse - previousAccumulatedImpulse;
        }
        else
        {
            accumulatedImpulse += lambda;
        }

        if (body1.dynamic)
        {
            body1.linearVelocity +=  jacobian[0] * lambda * body1.invMass;
            body1.angularVelocity += jacobian[1] * lambda * body1.invInertiaTensor;
        }
        if (body2.dynamic)
        {
            body2.linearVelocity +=  jacobian[2] * lambda * body2.invMass;
            body2.angularVelocity += jacobian[3] * lambda * body2.invInertiaTensor;
        }
    }
}

/*
 * Limits the translation so that the local anchor points of two rigid bodies
 * match in world space.
 */
class BallConstraint: Constraint
{
    Vector3f localAnchor1, localAnchor2;
    Vector3f r1, r2;

    Vector3f[4] jacobian;

    float accumulatedImpulse = 0.0f;

    float biasFactor = 0.1f;
    float softness = 0.01f; //0.05f;

    float softnessOverDt;
    float effectiveMass;
    float bias;

    this(Owner owner, RigidBody body1, RigidBody body2, Vector3f anchor1, Vector3f anchor2)
    {
        super(owner);

        this.body1 = body1;
        this.body2 = body2;

        localAnchor1 = anchor1;
        localAnchor2 = anchor2;
    }

    override void prepare(double delta)
    {
        Vector3f r1 = body1.orientation.rotate(localAnchor1);
        Vector3f r2 = body2.orientation.rotate(localAnchor2);

        Vector3f p1, p2, dp;
        p1 = body1.worldCenterOfMass + r1;
        p2 = body2.worldCenterOfMass + r2;

        dp = p2 - p1;

        float deltaLength = dp.length;
        Vector3f n = dp.normalized;

        jacobian[0] = -n;
        jacobian[1] = -cross(r1, n);
        jacobian[2] = n;
        jacobian[3] = cross(r2, n);

        effectiveMass =
            body1.invMass +
            body2.invMass +
            dot(jacobian[1] * body1.invInertiaTensor, jacobian[1]) +
            dot(jacobian[3] * body2.invInertiaTensor, jacobian[3]);

        softnessOverDt = softness / delta;
        effectiveMass += softnessOverDt;
        effectiveMass = 1.0f / effectiveMass;

        bias = deltaLength * biasFactor * (1.0f / delta);

        if (body1.dynamic)
        {
            body1.linearVelocity += jacobian[0] * body1.invMass * accumulatedImpulse;
            body1.angularVelocity += jacobian[1] * body1.invInertiaTensor * accumulatedImpulse;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += jacobian[2] * body2.invMass * accumulatedImpulse;
            body2.angularVelocity += jacobian[3] * body2.invInertiaTensor * accumulatedImpulse;
        }
    }

    override void step()
    {
        float jv =
            dot(body1.linearVelocity, jacobian[0]) +
            dot(body1.angularVelocity, jacobian[1]) +
            dot(body2.linearVelocity, jacobian[2]) +
            dot(body2.angularVelocity, jacobian[3]);

        float softnessScalar = accumulatedImpulse * softnessOverDt;
        float lambda = -effectiveMass * (jv + bias + softnessScalar);

        accumulatedImpulse += lambda;

        if (body1.dynamic)
        {
            body1.linearVelocity += jacobian[0] * body1.invMass * lambda;
            body1.angularVelocity += jacobian[1] * body1.invInertiaTensor * lambda;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += jacobian[2] * body2.invMass * lambda;
            body2.angularVelocity += jacobian[3] * body2.invInertiaTensor * lambda;
        }
    }
}

/*
 * Constraints a point on a body to be fixed on a line
 * which is fixed on another body.
 */
class SliderConstraint: Constraint
{
    Vector3f lineNormal;

    Vector3f localAnchor1, localAnchor2;
    Vector3f r1, r2;

    Vector3f[4] jacobian;

    float accumulatedImpulse = 0.0f;

    float biasFactor = 0.5f;
    float softness = 0.0f;

    float softnessOverDt;
    float effectiveMass;
    float bias;

    this(Owner owner, RigidBody body1, RigidBody body2, Vector3f lineStartPointBody1, Vector3f pointBody2)
    {
        super(owner);

        this.body1 = body1;
        this.body2 = body2;

        localAnchor1 = lineStartPointBody1;
        localAnchor2 = pointBody2;

        lineNormal = (lineStartPointBody1 + body1.worldCenterOfMass) -
                     (pointBody2 + body2.worldCenterOfMass);

        if (lineNormal.lengthsqr != 0.0f)
            lineNormal.normalize();
    }

    override void prepare(double delta)
    {
        Vector3f r1 = body1.orientation.rotate(localAnchor1);
        Vector3f r2 = body2.orientation.rotate(localAnchor2);

        Vector3f p1, p2, dp;
        p1 = body1.worldCenterOfMass + r1;
        p2 = body2.worldCenterOfMass + r2;

        dp = p2 - p1;

        Vector3f l = body1.orientation.rotate(lineNormal);

        Vector3f t = cross((p1 - p2), l);
        if (t.lengthsqr != 0.0f)
            t.normalize();
        t = cross(t, l);

        jacobian[0] = t;
        jacobian[1] = cross((r1 + p2 - p1), t);
        jacobian[2] = -t;
        jacobian[3] = -cross(r2, t);

        effectiveMass =
            body1.invMass +
            body2.invMass +
            dot(jacobian[1] * body1.invInertiaTensor, jacobian[1]) +
            dot(jacobian[3] * body2.invInertiaTensor, jacobian[3]);

        softnessOverDt = softness / delta;
        effectiveMass += softnessOverDt;

        if (effectiveMass != 0)
            effectiveMass = 1.0f / effectiveMass;

        bias = -cross(l, (p2 - p1)).length * biasFactor * (1.0f / delta);

        if (body1.dynamic)
        {
            body1.linearVelocity += body1.invMass * accumulatedImpulse * jacobian[0];
            body1.angularVelocity += accumulatedImpulse * jacobian[1] * body1.invInertiaTensor;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += body2.invMass * accumulatedImpulse * jacobian[2];
            body2.angularVelocity += accumulatedImpulse * jacobian[3] * body2.invInertiaTensor;
        }
    }

    override void step()
    {
        float jv =
            dot(body1.linearVelocity, jacobian[0]) +
            dot(body1.angularVelocity, jacobian[1]) +
            dot(body2.linearVelocity, jacobian[2]) +
            dot(body2.angularVelocity, jacobian[3]);

        float softnessScalar = accumulatedImpulse * softnessOverDt;
        float lambda = -effectiveMass * (jv + bias + softnessScalar);

        accumulatedImpulse += lambda;

        if (body1.dynamic)
        {
            body1.linearVelocity += body1.invMass * lambda * jacobian[0];
            body1.angularVelocity += lambda * jacobian[1] * body1.invInertiaTensor;
        }

        if (body2.dynamic)
        {
            body2.linearVelocity += body2.invMass * lambda * jacobian[2];
            body2.angularVelocity += lambda * jacobian[3] * body2.invInertiaTensor;
        }
    }
}

/*
 * Constraints bodies so that they always take the same rotation
 * relative to each other.
 */
class AngleConstraint: Constraint
{
    Vector3f[4] jacobian;

    Vector3f accumulatedImpulse = Vector3f(0, 0, 0);

    float biasFactor = 0.05f;
    float softness = 0.0f;

    float softnessOverDt;
    Matrix3x3f effectiveMass;
    Vector3f bias;

    this(Owner owner, RigidBody body1, RigidBody body2)
    {
        super(owner);
        this.body1 = body1;
        this.body2 = body2;
    }

    override void prepare(double dt)
    {
        effectiveMass = body1.invInertiaTensor + body2.invInertiaTensor;

        softnessOverDt = softness / dt;

        effectiveMass.a11 += softnessOverDt;
        effectiveMass.a22 += softnessOverDt;
        effectiveMass.a33 += softnessOverDt;

        effectiveMass = effectiveMass.inverse;

        Quaternionf dq = body2.orientation * body1.orientation.conj;
        Vector3f axis = dq.generator;
/*
        // Matrix version
        Matrix3x3f orientationDifference = Matrix3x3f.identity;
        auto rot1 = body1.orientation.toMatrix3x3;
        auto rot2 = body2.orientation.toMatrix3x3;
        Matrix3x3f q = orientationDifference * rot2 * rot1.inverse;

        Vector3f axis;
        float x = q.a32 - q.a23;
        float y = q.a13 - q.a31;
        float z = q.a21 - q.a12;
        float r = sqrt(x * x + y * y + z * z);
        float t = q.a11 + q.a22 + q.a33;
        float angle = atan2(r, t - 1);
        axis = Vector3f(x, y, z) * angle;
*/

        bias = axis * biasFactor * (-1.0f / dt);

        if (body1.dynamic)
            body1.angularVelocity += accumulatedImpulse * body1.invInertiaTensor;
        if (body2.dynamic)
            body2.angularVelocity += -accumulatedImpulse * body2.invInertiaTensor;
    }

    override void step()
    {
        Vector3f jv = body1.angularVelocity - body2.angularVelocity;
        Vector3f softnessVector = accumulatedImpulse * softnessOverDt;

        Vector3f lambda = -1.0f * (jv+bias+softnessVector) * effectiveMass;
        accumulatedImpulse += lambda;

        if (body1.dynamic)
            body1.angularVelocity += lambda * body1.invInertiaTensor;
        if (body2.dynamic)
            body2.angularVelocity += -lambda * body2.invInertiaTensor;
    }
}

/*
 * Constrains two bodies to rotate only around a single axis in worldspace.
 */
class AxisAngleConstraint: Constraint
{
    Vector3f axis;

    Vector3f localAxis1;
    Vector3f localAxis2;
    Vector3f localConstrAxis1;
    Vector3f localConstrAxis2;
    Vector3f worldConstrAxis1;
    Vector3f worldConstrAxis2;

    Vector3f accumulatedImpulse = Vector3f(0, 0, 0);

    float biasFactor = 0.4f;
    float softness = 0.0f;

    float softnessOverDt;
    Matrix3x3f effectiveMass;
    Vector3f bias;

    this(Owner owner, RigidBody body1, RigidBody body2, Vector3f axis)
    {
        super(owner);
        this.body1 = body1;
        this.body2 = body2;
        this.axis = axis;

        // Axis in body space
        this.localAxis1 = axis * body1.orientation.toMatrix3x3.transposed;
        this.localAxis2 = axis * body2.orientation.toMatrix3x3.transposed;

        localConstrAxis1 = cross(Vector3f(0, 1, 0), localAxis1);
        if (localConstrAxis1.lengthsqr < 0.001f)
            localConstrAxis1 = cross(Vector3f(1, 0, 0), localAxis1);

        localConstrAxis2 = cross(localAxis1, localConstrAxis1);
        localConstrAxis1.normalize();
        localConstrAxis2.normalize();
    }

    override void prepare(double dt)
    {
        effectiveMass = body1.invInertiaTensor + body2.invInertiaTensor;

        softnessOverDt = softness / dt;

        effectiveMass.a11 += softnessOverDt;
        effectiveMass.a22 += softnessOverDt;
        effectiveMass.a33 += softnessOverDt;

        effectiveMass = effectiveMass.inverse;

        auto rot1 = body1.orientation.toMatrix3x3;
        auto rot2 = body2.orientation.toMatrix3x3;

        Vector3f worldAxis1 = localAxis1 * rot1;
        Vector3f worldAxis2 = localAxis2 * rot2;

        worldConstrAxis1 = localConstrAxis1 * rot1;
        worldConstrAxis2 = localConstrAxis2 * rot2;

        Vector3f error = cross(worldAxis1, worldAxis2);

        Vector3f errorAxis = Vector3f(0, 0, 0);
        errorAxis.x = dot(error, worldConstrAxis1);
        errorAxis.y = dot(error, worldConstrAxis2);

        bias = errorAxis * biasFactor * (-1.0f / dt);

        Vector3f impulse;
        impulse.x = worldConstrAxis1.x * accumulatedImpulse.x
                  + worldConstrAxis2.x * accumulatedImpulse.y;
        impulse.y = worldConstrAxis1.y * accumulatedImpulse.x
                  + worldConstrAxis2.y * accumulatedImpulse.y;
        impulse.z = worldConstrAxis1.z * accumulatedImpulse.x
                  + worldConstrAxis2.z * accumulatedImpulse.y;

        if (body1.dynamic)
            body1.angularVelocity += impulse * body1.invInertiaTensor;
        if (body2.dynamic)
            body2.angularVelocity += -impulse * body2.invInertiaTensor;
    }

    override void step()
    {
        Vector3f vd = body1.angularVelocity - body2.angularVelocity;
        Vector3f jv = Vector3f(0, 0, 0);
        jv.x = dot(vd, worldConstrAxis1);
        jv.y = dot(vd, worldConstrAxis2);

        Vector3f softnessVector = accumulatedImpulse * softnessOverDt;

        Vector3f lambda = -(jv + bias + softnessVector) * effectiveMass;
        accumulatedImpulse += lambda;

        Vector3f impulse;
        impulse.x = worldConstrAxis1.x * lambda.x + worldConstrAxis2.x * lambda.y;
        impulse.y = worldConstrAxis1.y * lambda.x + worldConstrAxis2.y * lambda.y;
        impulse.z = worldConstrAxis1.z * lambda.x + worldConstrAxis2.z * lambda.y;

        if (body1.dynamic)
            body1.angularVelocity += impulse * body1.invInertiaTensor;
        if (body2.dynamic)
            body2.angularVelocity += -impulse * body2.invInertiaTensor;
    }
}

/*
 * Combination of SliderConstraint and AngleConstraint.
 * Restrics 5 degrees of freedom so that bodies can only move in one direction
 * relative to each other.
 */
class PrismaticConstraint: Constraint
{
    AngleConstraint ac;
    SliderConstraint sc;

    this(Owner owner, RigidBody body1, RigidBody body2)
    {
        super(owner);
        this.body1 = body1;
        this.body2 = body2;

        ac = New!AngleConstraint(this, body1, body2);
        sc = New!SliderConstraint(this, body1, body2,
            Vector3f(0, 0, 0), Vector3f(0, 0, 0));
    }

    override void prepare(double dt)
    {
        ac.prepare(dt);
        sc.prepare(dt);
    }

    override void step()
    {
        ac.step();
        sc.step();
    }
}

/*
 * Combination of BallConstraint and AxisAngleConstraint.
 * Restricts 5 degrees of freedom, so the bodies are fixed relative to
 * anchor point and can only rotate around one axis.
 * This can be useful to represent doors or wheels.
 */
class HingeConstraint: Constraint
{
    AxisAngleConstraint aac;
    BallConstraint bc;

    this(Owner owner, 
         RigidBody body1,
         RigidBody body2,
         Vector3f anchor1,
         Vector3f anchor2,
         Vector3f axis)
    {
        super(owner);
        this.body1 = body1;
        this.body2 = body2;

        aac = New!AxisAngleConstraint(this, body1, body2, axis);
        bc = New!BallConstraint(this, body1, body2, anchor1, anchor2);
    }

    override void prepare(double dt)
    {
        aac.prepare(dt);
        bc.prepare(dt);
    }

    override void step()
    {
        aac.step();
        bc.step();
    }
}
