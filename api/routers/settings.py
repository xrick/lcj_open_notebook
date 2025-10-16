from fastapi import APIRouter, HTTPException
from loguru import logger

from api.models import SettingsResponse, SettingsUpdate
from open_notebook.domain.content_settings import ContentSettings
from open_notebook.exceptions import DatabaseOperationError, InvalidInputError

router = APIRouter()


@router.get("/settings", response_model=SettingsResponse)
async def get_settings():
    """Get all application settings."""
    try:
        settings = await ContentSettings.get_instance()
        
        return SettingsResponse(
            default_content_processing_engine_doc=settings.default_content_processing_engine_doc,
            default_content_processing_engine_url=settings.default_content_processing_engine_url,
            default_embedding_option=settings.default_embedding_option,
            auto_delete_files=settings.auto_delete_files,
            youtube_preferred_languages=settings.youtube_preferred_languages,
        )
    except Exception as e:
        logger.error(f"Error fetching settings: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error fetching settings: {str(e)}")


@router.put("/settings", response_model=SettingsResponse)
async def update_settings(settings_update: SettingsUpdate):
    """Update application settings."""
    try:
        settings = await ContentSettings.get_instance()
        
        # Update only provided fields
        if settings_update.default_content_processing_engine_doc is not None:
            settings.default_content_processing_engine_doc = settings_update.default_content_processing_engine_doc
        if settings_update.default_content_processing_engine_url is not None:
            settings.default_content_processing_engine_url = settings_update.default_content_processing_engine_url
        if settings_update.default_embedding_option is not None:
            settings.default_embedding_option = settings_update.default_embedding_option
        if settings_update.auto_delete_files is not None:
            settings.auto_delete_files = settings_update.auto_delete_files
        if settings_update.youtube_preferred_languages is not None:
            settings.youtube_preferred_languages = settings_update.youtube_preferred_languages
        
        await settings.update()
        
        return SettingsResponse(
            default_content_processing_engine_doc=settings.default_content_processing_engine_doc,
            default_content_processing_engine_url=settings.default_content_processing_engine_url,
            default_embedding_option=settings.default_embedding_option,
            auto_delete_files=settings.auto_delete_files,
            youtube_preferred_languages=settings.youtube_preferred_languages,
        )
    except HTTPException:
        raise
    except InvalidInputError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Error updating settings: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error updating settings: {str(e)}")