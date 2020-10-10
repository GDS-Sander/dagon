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

module dagon.ui.freeview;

import std.math;

import dlib.math.vector;
import dlib.math.matrix;
import dlib.math.quaternion;
import dlib.math.transformation;
import dlib.math.utils;

import dagon.core.event;
import dagon.core.keycodes;
import dagon.core.time;
import dagon.graphics.entity;

class FreeviewComponent: EntityComponent
{
    int prevMouseX;
    int prevMouseY;
    float mouseSensibility = 0.1f;
    
    Vector3f center;
    float distance;
    Quaternionf rotPitch;
    Quaternionf rotTurn;
    Quaternionf rotRoll;
    Matrix4x4f transform;
    Matrix4x4f invTransform;

    float rotPitchTheta = 0.0f;
    float rotTurnTheta = 0.0f;
    float rotRollTheta = 0.0f;

    float pitchCurrentTheta = 0.0f;
    float pitchTargetTheta = 0.0f;
    float turnCurrentTheta = 0.0f;
    float turnTargetTheta = 0.0f;
    float rollCurrentTheta = 0.0f;
    float rollTargetTheta = 0.0f;

    float currentMove = 0.0f;
    float targetMove = 0.0f;

    float currentStrafe = 0.0f;
    float targetStrafe = 0.0f;

    float currentZoom = 0.0f;
    float targetZoom = 0.0f;

    bool zoomIn = false;
    float zoomSmoothFactor = 2.0f;
    float translateSmoothFactor = 10.0f;

    Vector3f currentTranslate;
    Vector3f targetTranslate;

    bool movingToTarget = false;
    
    bool active = true;
    
    this(EventManager em, Entity e)
    {
        super(em, e);
        
        center = Vector3f(0.0f, 0.0f, 0.0f);
        rotPitch = rotationQuaternion(Vector3f(1.0f,0.0f,0.0f), 0.0f);
        rotTurn = rotationQuaternion(Vector3f(0.0f,1.0f,0.0f), 0.0f);
        rotRoll = rotationQuaternion(Vector3f(0.0f,0.0f,1.0f), 0.0f);
        transform = Matrix4x4f.identity;
        invTransform = Matrix4x4f.identity;
        distance = 10.0f;
        
        currentTranslate = Vector3f(0.0f, 0.0f, 0.0f);
        targetTranslate = Vector3f(0.0f, 0.0f, 0.0f);
        
        pitch(45.0f);
        turn(45.0f);
        setZoom(20.0f);
    }
    
    void reset()
    {
        center = Vector3f(0.0f, 0.0f, 0.0f);
        rotPitch = rotationQuaternion(Vector3f(1.0f,0.0f,0.0f), 0.0f);
        rotTurn = rotationQuaternion(Vector3f(0.0f,1.0f,0.0f), 0.0f);
        rotRoll = rotationQuaternion(Vector3f(0.0f,0.0f,1.0f), 0.0f);
        transform = Matrix4x4f.identity;
        invTransform = Matrix4x4f.identity;
        distance = 10.0f;
        
        currentTranslate = Vector3f(0.0f, 0.0f, 0.0f);
        targetTranslate = Vector3f(0.0f, 0.0f, 0.0f);

        rotPitchTheta = 0.0f;
        rotTurnTheta = 0.0f;
        rotRollTheta = 0.0f;

        pitchCurrentTheta = 0.0f;
        pitchTargetTheta = 0.0f;
        turnCurrentTheta = 0.0f;
        turnTargetTheta = 0.0f;
        rollCurrentTheta = 0.0f;
        rollTargetTheta = 0.0f;

        currentMove = 0.0f;
        targetMove = 0.0f;

        currentStrafe = 0.0f;
        targetStrafe = 0.0f;

        currentZoom = 0.0f;
        targetZoom = 0.0f;
        
        pitch(45.0f);
        turn(45.0f);
        setZoom(20.0f);
    }
    
    override void update(Time time)
    {
        processEvents();
        
        if (active)
        {
            if (eventManager.mouseButtonPressed[MB_RIGHT])
            {
                float shiftx = (eventManager.mouseX - prevMouseX) * mouseSensibility;
                float shifty = -(eventManager.mouseY - prevMouseY) * mouseSensibility;
                Vector3f trans = up * shifty + right * shiftx;
                translateTarget(trans);
            }
            else if (eventManager.mouseButtonPressed[MB_LEFT] && eventManager.keyPressed[KEY_LCTRL])
            {
                float shiftx = (eventManager.mouseX - prevMouseX);
                float shifty = (eventManager.mouseY - prevMouseY);
                zoom((shiftx + shifty) * 0.1f);
            }
            else if (eventManager.mouseButtonPressed[MB_LEFT])
            {                
                float t = (eventManager.mouseX - prevMouseX);
                float p = (eventManager.mouseY - prevMouseY);
                pitchSmooth(p, 4.0f);
                turnSmooth(t, 4.0f);
            }

            prevMouseX = eventManager.mouseX;
            prevMouseY = eventManager.mouseY;
        }
    
        if (currentZoom < targetZoom)
        {
            currentZoom += (targetZoom - currentZoom) / zoomSmoothFactor;
            if (zoomIn)
                zoom((targetZoom - currentZoom) / zoomSmoothFactor);
            else
                zoom(-(targetZoom - currentZoom) / zoomSmoothFactor);
        }
        if (currentTranslate != targetTranslate)
        {
            Vector3f t = (targetTranslate - currentTranslate) / translateSmoothFactor;
            currentTranslate += t;
            translateTarget(t);
        }

        rotPitch = rotationQuaternion(Vector3f(1.0f,0.0f,0.0f), degtorad(rotPitchTheta));
        rotTurn = rotationQuaternion(Vector3f(0.0f,1.0f,0.0f), degtorad(rotTurnTheta));
        rotRoll = rotationQuaternion(Vector3f(0.0f,0.0f,1.0f), degtorad(rotRollTheta));

        Quaternionf q = rotPitch * rotTurn * rotRoll;
        Matrix4x4f rot = q.toMatrix4x4();
        invTransform = translationMatrix(Vector3f(0.0f, 0.0f, -distance)) * rot * translationMatrix(center);

        transform = invTransform.inverse;
        
        entity.prevTransformation = entity.transformation;
        entity.transformation = transform;
        entity.invTransformation = invTransform;
        
        entity.absoluteTransformation = entity.transformation;
        entity.invAbsoluteTransformation = entity.invTransformation;
        entity.prevAbsoluteTransformation = entity.prevTransformation;
    }
    
    void setRotation(float p, float t, float r)
    {
        rotPitchTheta = p;
        rotTurnTheta = t;
        rotRollTheta = r;
    }
    
    void pitch(float theta)
    {
        rotPitchTheta += theta;
    }

    void turn(float theta)
    {
        rotTurnTheta += theta;
    }

    void roll(float theta)
    {
        rotRollTheta += theta;
    }

    float pitch()
    {
        return rotPitchTheta;
    }

    float turn()
    {
        return rotTurnTheta;
    }

    float roll()
    {
        return rotRollTheta;
    }

    void pitchSmooth(float theta, float smooth)
    {
        pitchTargetTheta += theta;
        float pitchTheta = (pitchTargetTheta - pitchCurrentTheta) / smooth;
        pitchCurrentTheta += pitchTheta;
        pitch(pitchTheta);
    }

    void turnSmooth(float theta, float smooth)
    {
        turnTargetTheta += theta;
        float turnTheta = (turnTargetTheta - turnCurrentTheta) / smooth;
        turnCurrentTheta += turnTheta;
        turn(turnTheta);
    }

    void rollSmooth(float theta, float smooth)
    {
        rollTargetTheta += theta;
        float rollTheta = (rollTargetTheta - rollCurrentTheta) / smooth;
        rollCurrentTheta += rollTheta;
        roll(rollTheta);
    }

    void setTargetSmooth(Vector3f pos, float smooth)
    {
        currentTranslate = center;
        targetTranslate = -pos;
    }

    void translateTarget(Vector3f pos)
    {
        center += pos;
    }

    void setZoom(float z)
    {
        distance = z;
    }

    void zoom(float z)
    {
        distance -= z;
    }

    void zoomSmooth(float z, float smooth)
    {
        zoomSmoothFactor = smooth;

        if (z < 0)
            zoomIn = true;
        else
            zoomIn = false;

        targetZoom += abs(z);
    }

    Vector3f position()
    {
        return transform.translation();
    }

    Vector3f right()
    {
        return transform.right();
    }

    Vector3f up()
    {
        return transform.up();
    }

    Vector3f direction()
    {
        return transform.forward();
    }

    void strafe(float speed)
    {
        Vector3f forward;
        forward.x = cos(degtorad(rotTurnTheta));
        forward.y = 0.0f;
        forward.z = sin(degtorad(rotTurnTheta));
        center += forward * speed;
    }

    void strafeSmooth(float speed, float smooth)
    {
        targetMove += speed;
        float movesp = (targetMove - currentMove) / smooth;
        currentMove += movesp;
        strafe(movesp);
    }

    void move(float speed)
    {
        Vector3f dir;
        dir.x = cos(degtorad(rotTurnTheta + 90.0f));
        dir.y = 0.0f;
        dir.z = sin(degtorad(rotTurnTheta + 90.0f));
        center += dir * speed;
    }

    void moveSmooth(float speed, float smooth)
    {
        targetStrafe += speed;
        float strafesp = (targetStrafe - currentStrafe) / smooth;
        currentStrafe += strafesp;
        move(strafesp);
    }

    void screenToWorld(
        int scrx,
        int scry,
        int scrw,
        int scrh,
        float yfov,
        ref float worldx,
        ref float worldy,
        bool snap)
    {
        Vector3f camPos = position();
        Vector3f camDir = direction();

        float aspect = cast(float)scrw / cast(float)scrh;

        float xfov = fovXfromY(yfov, aspect);

        float tfov1 = tan(yfov*PI/360.0f);
        float tfov2 = tan(xfov*PI/360.0f);

        Vector3f camUp = up() * tfov1;
        Vector3f camRight = right() * tfov2;

        float width  = 1.0f - 2.0f * cast(float)(scrx) / cast(float)(scrw);
        float height = 1.0f - 2.0f * cast(float)(scry) / cast(float)(scrh);

        float mx = camDir.x + camUp.x * height + camRight.x * width;
        float my = camDir.y + camUp.y * height + camRight.y * width;
        float mz = camDir.z + camUp.z * height + camRight.z * width;

        worldx = snap? floor(camPos.x - mx * camPos.y / my) : (camPos.x - mx * camPos.y / my);
        worldy = snap? floor(camPos.z - mz * camPos.y / my) : (camPos.z - mz * camPos.y / my);
    }
    
    override void onMouseButtonDown(int button)
    {
        if (!active)
            return;
    
        if (button == MB_LEFT)
        {
            prevMouseX = eventManager.mouseX;
            prevMouseY = eventManager.mouseY;
        }
    }
    
    override void onMouseWheel(int x, int y)
    {
        if (!active)
            return;
            
        zoom(cast(float)y * 0.2f);
    }
}
