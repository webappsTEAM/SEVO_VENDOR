"""
workforce_api/skill_requirement_views.py
API views for Service-to-Skill Requirements configuration.
"""
import logging
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import WorkforceServiceSkillRequirement, WorkforceSkill

logger = logging.getLogger(__name__)


class ServiceSkillRequirementsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        service_id = request.query_params.get("service_id")
        qs = WorkforceServiceSkillRequirement.objects.select_related("skill", "service")
        if service_id:
            qs = qs.filter(service_id=service_id)

        data = [
            {
                "id": req.id,
                "service_id": req.service_id,
                "service_name": req.service.name if req.service else "",
                "skill_id": req.skill_id,
                "skill_name": req.skill.name if req.skill else "",
                "is_mandatory": req.is_mandatory,
                "created_at": req.created_at.isoformat() if req.created_at else None,
            }
            for req in qs
        ]
        return Response(data, status=status.HTTP_200_OK)

    def post(self, request):
        service_id = request.data.get("service_id")
        skill_id = request.data.get("skill_id")
        is_mandatory = bool(request.data.get("is_mandatory", True))

        if not service_id or not skill_id:
            return Response(
                {"error": "service_id and skill_id are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            req, created = WorkforceServiceSkillRequirement.objects.update_or_create(
                service_id=service_id,
                skill_id=skill_id,
                defaults={"is_mandatory": is_mandatory},
            )
            return Response(
                {
                    "id": req.id,
                    "service_id": req.service_id,
                    "skill_id": req.skill_id,
                    "skill_name": req.skill.name if req.skill else "",
                    "is_mandatory": req.is_mandatory,
                },
                status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
            )
        except Exception as exc:
            logger.error(f"[SERVICE_SKILL_REQUIREMENT_ERR] {exc}")
            return Response(
                {"error": str(exc)},
                status=status.HTTP_400_BAD_REQUEST,
            )
