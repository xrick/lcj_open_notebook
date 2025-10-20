from typing import Dict, List, Union

from fastapi import APIRouter, HTTPException
from loguru import logger

from api.models import ContextRequest, ContextResponse
from open_notebook.domain.base import ObjectModel
from open_notebook.domain.notebook import Note, Notebook, Source
from open_notebook.exceptions import DatabaseOperationError, InvalidInputError
from open_notebook.utils import token_count

router = APIRouter()


@router.post("/notebooks/{notebook_id}/context", response_model=ContextResponse)
async def get_notebook_context(notebook_id: str, context_request: ContextRequest):
    """Get context for a notebook based on configuration."""
    try:
        # Verify notebook exists
        notebook = await Notebook.get(notebook_id)
        if not notebook:
            raise HTTPException(status_code=404, detail="Notebook not found")

        context_data = {"note": [], "source": []}
        total_content = ""

        # Process context configuration if provided
        if context_request.context_config:
            # Process sources
            for source_id, status in context_request.context_config.sources.items():
                if "not in" in status:
                    continue

                try:
                    # Add table prefix if not present
                    full_source_id = (
                        source_id
                        if source_id.startswith("source:")
                        else f"source:{source_id}"
                    )

                    try:
                        source = await Source.get(full_source_id)
                        if not source:
                            logger.warning(f"Source not found: {source_id}")
                            continue
                    except Exception as e:
                        logger.warning(f"Error loading source {source_id}: {str(e)}")
                        continue

                    if "insights" in status:
                        try:
                            source_context = await source.get_context(context_size="short")
                            context_data["source"].append(source_context)
                            total_content += str(source_context)
                        except Exception as e:
                            logger.error(f"Error getting short context for source {source_id}: {str(e)}")
                            # Include minimal info so user knows something went wrong
                            context_data["source"].append({
                                "id": source.id,
                                "title": source.title or "Untitled",
                                "insights": [],
                                "error": "Failed to load insights"
                            })
                    elif "full content" in status:
                        try:
                            source_context = await source.get_context(context_size="long")
                            context_data["source"].append(source_context)
                            total_content += str(source_context)
                        except Exception as e:
                            logger.error(f"Error getting full context for source {source_id}: {str(e)}")
                            # Try fallback to short context
                            try:
                                logger.info(f"Attempting fallback to short context for {source_id}")
                                source_context = await source.get_context(context_size="short")
                                context_data["source"].append(source_context)
                                total_content += str(source_context)
                                logger.info(f"Fallback to short context successful for {source_id}")
                            except Exception as fallback_error:
                                logger.error(f"Fallback also failed for {source_id}: {str(fallback_error)}")
                                # Include error info so chat can continue
                                context_data["source"].append({
                                    "id": source.id,
                                    "title": source.title or "Untitled",
                                    "insights": [],
                                    "error": "Failed to load content"
                                })
                except Exception as e:
                    logger.error(f"Unexpected error processing source {source_id}: {str(e)}", exc_info=True)
                    continue

            # Process notes
            for note_id, status in context_request.context_config.notes.items():
                if "not in" in status:
                    continue

                try:
                    # Add table prefix if not present
                    full_note_id = (
                        note_id if note_id.startswith("note:") else f"note:{note_id}"
                    )
                    note = await Note.get(full_note_id)
                    if not note:
                        continue

                    if "full content" in status:
                        note_context = note.get_context(context_size="long")
                        context_data["note"].append(note_context)
                        total_content += str(note_context)
                except Exception as e:
                    logger.warning(f"Error processing note {note_id}: {str(e)}")
                    continue
        else:
            # Default behavior - include all sources and notes with short context
            sources = await notebook.get_sources()
            for source in sources:
                try:
                    source_context = await source.get_context(context_size="short")
                    context_data["source"].append(source_context)
                    total_content += str(source_context)
                except Exception as e:
                    logger.error(f"Error processing source {source.id}: {str(e)}", exc_info=True)
                    # Include error info so user knows this source had issues
                    try:
                        context_data["source"].append({
                            "id": source.id,
                            "title": source.title or "Untitled",
                            "insights": [],
                            "error": "Failed to load context"
                        })
                    except Exception:
                        # Even error handling failed, skip this source
                        continue

            notes = await notebook.get_notes()
            for note in notes:
                try:
                    note_context = note.get_context(context_size="short")
                    context_data["note"].append(note_context)
                    total_content += str(note_context)
                except Exception as e:
                    logger.warning(f"Error processing note {note.id}: {str(e)}")
                    continue

        # Calculate estimated token count
        estimated_tokens = token_count(total_content) if total_content else 0

        return ContextResponse(
            notebook_id=notebook_id,
            sources=context_data["source"],
            notes=context_data["note"],
            total_tokens=estimated_tokens,
        )

    except HTTPException:
        raise
    except InvalidInputError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Error getting context for notebook {notebook_id}: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error getting context: {str(e)}")
