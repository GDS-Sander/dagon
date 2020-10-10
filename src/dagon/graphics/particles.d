/*
Copyright (c) 2017-2020 Timur Gafarov

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

module dagon.graphics.particles;

import std.math;
import std.random;
import std.algorithm;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.math.transformation;
import dlib.math.interpolation;
import dlib.math.utils;
import dlib.image.color;
import dlib.container.array;

import dagon.core.time;
import dagon.core.event;
import dagon.core.bindings;
import dagon.graphics.entity;
import dagon.graphics.texture;
import dagon.graphics.state;
import dagon.graphics.material;
import dagon.graphics.mesh;

struct Particle
{
    Color4f startColor;
    Color4f color;
    Vector3f position;
    Vector3f positionPrev;
    Vector3f acceleration;
    Vector3f velocity;
    Vector3f gravityVector;
    Vector3f scale;
    float rotation;
    float rotationDirection;
    double lifetime;
    double time;
    bool move;
    bool active;
}

abstract class ForceField: EntityComponent
{
    this(Entity e, ParticleSystem psys)
    {
        super(psys.eventManager, e);
        psys.addForceField(this);
    }

    void affect(ref Particle p);
}

class Attractor: ForceField
{
    float g;

    this(Entity e, ParticleSystem psys, float magnitude)
    {
        super(e, psys);
        g = magnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float d = max(EPSILON, r.length);
        p.acceleration += r * -g / (d * d);
    }
}

class Deflector: ForceField
{
    float g;

    this(Entity e, ParticleSystem psys, float magnitude)
    {
        super(e, psys);
        g = magnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float d = max(EPSILON, r.length);
        p.acceleration += r * g / (d * d);
    }
}

class Vortex: ForceField
{
    float g1;
    float g2;

    this(Entity e, ParticleSystem psys, float tangentMagnitude, float normalMagnitude)
    {
        super(e, psys);
        g1 = tangentMagnitude;
        g2 = normalMagnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f direction = entity.transformation.forward;
        float proj = dot(p.position, direction);
        Vector3f pos = entity.position + direction * proj;
        Vector3f r = p.position - pos;
        float d = max(EPSILON, r.length);
        Vector3f t = lerp(r, cross(r, direction), 0.25f);
        p.acceleration += direction * g2 - t * g1 / (d * d);
    }
}

class BlackHole: ForceField
{
    float g;

    this(Entity e, ParticleSystem psys, float magnitude)
    {
        super(e, psys);
        g = magnitude;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float d = r.length;
        if (d <= 0.001f)
            p.time = p.lifetime;
        else
            p.acceleration += r * -g / (d * d);
    }
}

class ColorChanger: ForceField
{
    Color4f color;
    float outerRadius;
    float innerRadius;

    this(Entity e, ParticleSystem psys, Color4f color, float outerRadius, float innerRadius)
    {
        super(e, psys);
        this.color = color;
        this.outerRadius = outerRadius;
        this.innerRadius = innerRadius;
    }

    override void affect(ref Particle p)
    {
        Vector3f r = p.position - entity.position;
        float t = clamp((r.length - innerRadius) / outerRadius, 0.0f, 1.0f);
        p.color = lerp(color, p.color, t);
    }
}

class Emitter: EntityComponent
{
    Particle[] particles;

    double minLifetime = 1.0;
    double maxLifetime = 3.0;

    float minSize = 0.25f;
    float maxSize = 1.0f;
    Vector3f scaleStep = Vector3f(0, 0, 0);

    float rotationStep = 0.0f;

    float initialPositionRandomRadius = 0.0f;

    float minInitialSpeed = 1.0f;
    float maxInitialSpeed = 5.0f;

    Vector3f initialDirection = Vector3f(0, 1, 0);
    float initialDirectionRandomFactor = 1.0f;

    Color4f startColor = Color4f(1, 1, 1, 1);
    Color4f endColor = Color4f(1, 1, 1, 0);

    float airFrictionDamping = 0.98f;

    bool emitting = true;

    Material material;

    Entity particleEntity;

    this(Entity e, ParticleSystem psys, uint numParticles)
    {
        super(psys.eventManager, e);

        psys.addEmitter(this);

        particles = New!(Particle[])(numParticles);
        foreach(ref p; particles)
        {
            resetParticle(p);
        }
    }

    ~this()
    {
        Delete(particles);
    }

    void resetParticle(ref Particle p)
    {
        Vector3f posAbsolute = entity.positionAbsolute;

        if (initialPositionRandomRadius > 0.0f)
        {
            float randomDist = uniform(0.0f, initialPositionRandomRadius);
            p.position = posAbsolute + randomUnitVector3!float * randomDist;
        }
        else
            p.position = posAbsolute;

        p.positionPrev = p.position;

        Vector3f r = randomUnitVector3!float;

        float initialSpeed;
        if (maxInitialSpeed > minInitialSpeed)
            initialSpeed = uniform(minInitialSpeed, maxInitialSpeed);
        else
            initialSpeed = maxInitialSpeed;
        p.velocity = lerp(initialDirection, r, initialDirectionRandomFactor) * initialSpeed;

        if (maxLifetime > minLifetime)
            p.lifetime = uniform(minLifetime, maxLifetime);
        else
            p.lifetime = maxLifetime;
        p.gravityVector = Vector3f(0, -1, 0);

        float s;
        if (maxSize > maxSize)
            s = uniform(maxSize, maxSize);
        else
            s = maxSize;

        p.rotation = uniform(0.0f, 2.0f * PI);
        p.rotationDirection = choice([1.0f, -1.0f]);
        p.scale = Vector3f(s, s, s);
        p.time = 0.0f;
        p.move = true;
        p.startColor = startColor;
        p.color = p.startColor;
    }
}

class ParticleSystem: EntityComponent
{
    EventManager eventManager;

    Array!Emitter emitters;
    Array!ForceField forceFields;

    Vector3f[4] vertices;
    Vector2f[4] texcoords;
    uint[3][2] indices;

    GLuint vao = 0;
    GLuint vbo = 0;
    GLuint tbo = 0;
    GLuint eao = 0;

    Matrix4x4f invViewMatRot;

    bool haveParticlesToDraw = false;

    bool useMotionBlur = true;

    this(EventManager eventManager, Entity e)
    {
        super(eventManager, e);
        this.eventManager = eventManager;

        vertices[0] = Vector3f(-0.5f, 0.5f, 0);
        vertices[1] = Vector3f(-0.5f, -0.5f, 0);
        vertices[2] = Vector3f(0.5f, -0.5f, 0);
        vertices[3] = Vector3f(0.5f, 0.5f, 0);

        texcoords[0] = Vector2f(0, 0);
        texcoords[1] = Vector2f(0, 1);
        texcoords[2] = Vector2f(1, 1);
        texcoords[3] = Vector2f(1, 0);

        indices[0][0] = 0;
        indices[0][1] = 1;
        indices[0][2] = 2;

        indices[1][0] = 0;
        indices[1][1] = 2;
        indices[1][2] = 3;

        glGenBuffers(1, &vbo);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glBufferData(GL_ARRAY_BUFFER, vertices.length * float.sizeof * 3, vertices.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &tbo);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glBufferData(GL_ARRAY_BUFFER, texcoords.length * float.sizeof * 2, texcoords.ptr, GL_STATIC_DRAW);

        glGenBuffers(1, &eao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.length * uint.sizeof * 3, indices.ptr, GL_STATIC_DRAW);

        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, eao);

        glEnableVertexAttribArray(VertexAttrib.Vertices);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);
        glVertexAttribPointer(VertexAttrib.Vertices, 3, GL_FLOAT, GL_FALSE, 0, null);

        glEnableVertexAttribArray(VertexAttrib.Texcoords);
        glBindBuffer(GL_ARRAY_BUFFER, tbo);
        glVertexAttribPointer(VertexAttrib.Texcoords, 2, GL_FLOAT, GL_FALSE, 0, null);

        glBindVertexArray(0);
    }

    ~this()
    {
        emitters.free();
        forceFields.free();
    }

    void addForceField(ForceField ff)
    {
        forceFields.append(ff);
    }

    void addEmitter(Emitter em)
    {
        emitters.append(em);
    }

    void updateParticle(Emitter e, ref Particle p, double dt)
    {
        p.time += dt;

        float t = p.time / p.lifetime;
        p.color = lerp(e.startColor, e.endColor, t);
        p.scale = p.scale + e.scaleStep * dt;
        p.rotation = p.rotation + e.rotationStep * p.rotationDirection * dt;

        if (p.move)
        {
            p.acceleration = Vector3f(0, 0, 0);

            foreach(ref ff; forceFields)
            {
                ff.affect(p);
            }

            p.velocity += p.acceleration * dt;
            p.velocity = p.velocity * e.airFrictionDamping;

            p.positionPrev = p.position;
            p.position += p.velocity * dt;
        }

        p.color.a = lerp(e.startColor.a, e.endColor.a, t);
    }

    override void update(Time t)
    {
        haveParticlesToDraw = false;

        foreach(e; emitters)
        foreach(ref p; e.particles)
        {
            if (p.active)
            {
                if (p.time < p.lifetime)
                {
                    updateParticle(e, p, t.delta);
                    haveParticlesToDraw = true;
                }
                else
                    p.active = false;
            }
            else if (e.emitting)
            {
                e.resetParticle(p);
                p.active = true;
            }
        }
    }

    override void render(GraphicsState* state)
    {
        if (haveParticlesToDraw)
        {
            foreach(e; emitters)
            if (e.entity.visible)
            {
                bool shouldRender = true;
                //if (state.shadowPass)
                //    shouldRender = e.entity.castShadow;

                if (shouldRender)
                {
                    if (e.material)
                        e.entity.material = e.material;

                    foreach(ref p; e.particles)
                    if (p.time < p.lifetime)
                    {
                        //if (e.particleEntity)
                        //    renderEntityParticle(e, p, state);
                        //else
                            renderBillboardParticle(e, p, state);
                    }
                }
            }
        }
    }

    /*
    void renderEntityParticle(Emitter e, ref Particle p, GraphicsState* state)
    {
        auto stateLocal = *state;

        Matrix4x4f trans =
            translationMatrix(p.position);

        Matrix4x4f prevTrans =
            translationMatrix(p.positionPrev);

        auto absTrans = e.particleEntity.absoluteTransformation;
        auto invAbsTrans = e.particleEntity.invAbsoluteTransformation;
        auto prevAbsTrans = e.particleEntity.prevAbsoluteTransformation;

        e.particleEntity.absoluteTransformation = trans;
        e.particleEntity.invAbsoluteTransformation = trans.inverse;
        e.particleEntity.prevAbsoluteTransformation = prevTrans;

        foreach(child; e.particleEntity.children)
        {
            child.updateTransformation();
        }

        e.particleEntity.render(&stateLocal);

        e.particleEntity.absoluteTransformation = absTrans;
        e.particleEntity.invAbsoluteTransformation = invAbsTrans;
        e.particleEntity.prevAbsoluteTransformation = prevAbsTrans;
    }
    */

    void renderBillboardParticle(Emitter e, ref Particle p, GraphicsState* state)
    {
        Matrix4x4f trans = translationMatrix(p.position);
        Matrix4x4f prevTrans = translationMatrix(p.positionPrev);

        Matrix4x4f modelViewMatrix =
            state.viewMatrix *
            translationMatrix(p.position) *
            state.invViewRotationMatrix *
            rotationMatrix(Axis.z, p.rotation) *
            scaleMatrix(Vector3f(p.scale.x, p.scale.y, 1.0f));

        GraphicsState stateLocal = *state;
        stateLocal.modelViewMatrix = modelViewMatrix;

        if (useMotionBlur)
            stateLocal.prevModelViewMatrix = stateLocal.prevViewMatrix * prevTrans;
        else
            stateLocal.prevModelViewMatrix = stateLocal.viewMatrix * trans;

        if (e.material)
        {
            e.material.particleColor = p.color;
            e.material.bind(&stateLocal);
        }

        if (stateLocal.shader)
        {
            stateLocal.shader.bindParameters(&stateLocal);
        }

        glBindVertexArray(vao);
        glDrawElements(GL_TRIANGLES, cast(uint)indices.length * 3, GL_UNSIGNED_INT, cast(void*)0);
        glBindVertexArray(0);

        if (stateLocal.shader)
        {
            stateLocal.shader.unbindParameters(&stateLocal);
        }

        if (e.material)
        {
            e.material.unbind(&stateLocal);
        }
    }
}

bool entityIsParticleSystem(Entity e)
{
    foreach(comp; e.components.data)
    {
        ParticleSystem psys = cast(ParticleSystem)comp;
        if (psys)
            return true;
    }
    return false;
}
